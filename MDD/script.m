% Setup script directory
scriptFolder = fileparts(mfilename('fullpath'));
if isempty(scriptFolder)
    scriptFolder = pwd; 
end

folderNames = {
    'Efficiency'
    'Open-circuit'
    'torque-speed-envelope'
    };
outputFile = fullfile(scriptFolder, 'MasterDataSheetTest.xlsx');

% --- CONSTANTS ---
EXCEL_ROW_LIMIT = 1048000; % Leave a buffer below Excel's strict limit
BUFFER_ROW_LIMIT = 150000; % Write to Excel in batches to speed up I/O

% Initialize or read the existing File Index and Data Dictionary
if isfile(outputFile)
    % Read File Lookup sheet
    fileTable = readtable(outputFile, 'Sheet', 'File Lookup');
    if isempty(fileTable)
        latestFileId = 0;
        existingFiles = strings(0, 1);
    else
        latestFileId = fileTable.FileID(end);
        existingFiles = string(fileTable.FileName);
    end
    
    % Read Description sheet to see what channels we already know about
    try
        dictTable = readtable(outputFile, 'Sheet', 'Description');
        knownChannels = string(dictTable.Channel_Name)';
    catch
        knownChannels = strings(1, 0);
    end
else
    % Create a fresh workbook and forcefully lock in the two metadata sheets
    disp('Initializing new workbook. Reserving file lookup and description sheets...');
    
    dummyIndex = cell2table(cell(0,2), 'VariableNames', {'FileID', 'FileName'});
    writetable(dummyIndex, outputFile, 'Sheet', 'file lookup'); 
    
    dummyDict = cell2table(cell(0,3), 'VariableNames', {'Channel_Name', 'Description', 'Unit'});
    writetable(dummyDict, outputFile, 'Sheet', 'description'); 
    
    latestFileId = 0;
    existingFiles = strings(0, 1);
    knownChannels = strings(1, 0);
end

% Loop through each folder
for i = 1:length(folderNames)
    testType = folderNames{i};
    currentFolderPath = fullfile(scriptFolder, testType);
    files = dir(fullfile(currentFolderPath, '**', '*.tdms'));
    
    % Excel sheet names are strictly limited to 31 characters. 
    % Truncate to 25 chars to leave room for "_Pt12" suffixes.
    if strlength(testType) > 25
        baseSheetName = char(extractBefore(string(testType), 26));
    else
        baseSheetName = char(testType);
    end
    
    folderPartCounter = 1;
    currentSheetName = baseSheetName;
    
    % 1. Find the active/latest Overflow Sheet if resuming
    if isfile(outputFile)
        while true
            if folderPartCounter == 1
                testName = baseSheetName;
            else
                testName = sprintf('%s_Pt%d', baseSheetName, folderPartCounter);
            end
            
            try
                % If this succeeds, the sheet exists.
                opts = detectImportOptions(outputFile, 'Sheet', testName);
                currentSheetName = testName; 
                folderPartCounter = folderPartCounter + 1; 
            catch
                break;
            end
        end
    end
    
    % 2. Count rows in the active sheet
    disp(['Checking row count for sheet: ', currentSheetName, '...']);
    try
        opts = detectImportOptions(outputFile, 'Sheet', currentSheetName);
        opts.SelectedVariableNames = opts.VariableNames(1); 
        existingData = readtable(outputFile, opts, 'Sheet', currentSheetName);
        currentSheetRows = height(existingData) + 1; 
    catch
        currentSheetRows = 1; 
    end
    
    % Initialize Data Buffers
    folderDataBuffer = table();
    indexDataBuffer = table();
    dictDataBuffer = table(); % Buffer for newly discovered channels
    
    for j = 1:length(files)
        currentFileName = files(j).name;
        filePath = fullfile(files(j).folder, currentFileName);
        
        if ismember(string(currentFileName), existingFiles)
            fprintf('File %s already loaded\n', currentFileName);
        else
            % CONTINUOUS NUMBERING: This guarantees FirstID = LastID + 1
            latestFileId = latestFileId + 1;
            
            fprintf('Loading %s into memory buffer... \n', currentFileName);
            newTableData = prepareTdmsData(filePath, latestFileId);
            numRows = height(newTableData);
            
            % --- EXAMINE CHANNELS FOR DESCRIPTION SHEET ---
            currentVars = string(newTableData.Properties.VariableNames);
            newVars = setdiff(currentVars, knownChannels, 'stable');
            
            if ~isempty(newVars)
                knownChannels = [knownChannels, newVars]; % Add to known memory
                % Stage new dictionary rows with completely empty strings
                newDictRows = table(newVars', repmat("", length(newVars), 1), repmat("", length(newVars), 1), ...
                    'VariableNames', {'Channel_Name', 'Description', 'Unit'});
                dictDataBuffer = [dictDataBuffer; newDictRows];
            end
            
            % --- EXCEL LIMIT CHECK & OVERFLOW TRIGGER ---
            if (currentSheetRows + numRows) >= EXCEL_ROW_LIMIT
                % Flush whatever is currently in the buffer to the OLD sheet
                if height(folderDataBuffer) > 0
                    fprintf('--> Sheet %s is full. Flushing buffer...\n', currentSheetName);
                    writetable(folderDataBuffer, outputFile, 'Sheet', currentSheetName, 'WriteMode', 'append');
                    writetable(indexDataBuffer, outputFile, 'Sheet', 'file lookup', 'WriteMode', 'append');
                    if height(dictDataBuffer) > 0
                        writetable(dictDataBuffer, outputFile, 'Sheet', 'description', 'WriteMode', 'append');
                        dictDataBuffer = table();
                    end
                    folderDataBuffer = table();
                    indexDataBuffer = table();
                end
                
                % Setup the new overflow sheet
                if folderPartCounter == 1
                    folderPartCounter = 2; % Edge case safety
                end
                currentSheetName = sprintf('%s_Part%d', baseSheetName, folderPartCounter);
                folderPartCounter = folderPartCounter + 1;
                currentSheetRows = 1; % Reset row count for the brand new sheet
                
                fprintf('\n>>> CREATING OVERFLOW SHEET: %s <<<\n', currentSheetName);
            end
            
            % Add to buffers and counters safely
            newIndexRow = table(latestFileId, {currentFileName}, 'VariableNames', {'FileID', 'FileName'});
            indexDataBuffer = [indexDataBuffer; newIndexRow];
            folderDataBuffer = [folderDataBuffer; newTableData];
            
            currentSheetRows = currentSheetRows + numRows;
            existingFiles(end+1) = string(currentFileName);
            
            % Standard Memory Chunking: Flush buffer if it gets too large
            if height(folderDataBuffer) >= BUFFER_ROW_LIMIT
                fprintf('--> Buffer reached %d rows. Flushing chunk to %s...\n', height(folderDataBuffer), currentSheetName);
                writetable(folderDataBuffer, outputFile, 'Sheet', currentSheetName, 'WriteMode', 'append');
                writetable(indexDataBuffer, outputFile, 'Sheet', 'file lookup', 'WriteMode', 'append');
                
                % Flush any new channels to Description sheet
                if height(dictDataBuffer) > 0
                    writetable(dictDataBuffer, outputFile, 'Sheet', 'description', 'WriteMode', 'append');
                    dictDataBuffer = table();
                end
                
                % Clear buffers
                folderDataBuffer = table();
                indexDataBuffer = table();
            end
        end
    end
    
    % End of folder: Flush any remaining data in the buffer
    if height(folderDataBuffer) > 0
        fprintf('--> Flushing final chunk for %s to %s...\n', testType, currentSheetName);
        writetable(folderDataBuffer, outputFile, 'Sheet', currentSheetName, 'WriteMode', 'append');
        writetable(indexDataBuffer, outputFile, 'Sheet', 'file lookup', 'WriteMode', 'append');
        
        if height(dictDataBuffer) > 0
            writetable(dictDataBuffer, outputFile, 'Sheet', 'description', 'WriteMode', 'append');
            dictDataBuffer = table();
        end
    end
end

disp('All TDMS files consolidated and processed successfully!');

%% --- LOCAL FUNCTIONS ---

function preparedData = prepareTdmsData(filepath, fileTableID)
    loadFile = tdmsread(filepath);
    data = loadFile{1};
    
    if istimetable(data)
        data = timetable2table(data, 'ConvertRowTimes', false);
    elseif ~istable(data)
        data = array2table(data);
    end
    
    data = addvars(data, (1:height(data))', 'Before', 1, 'NewVariableNames', 'SampleID');
    preparedData = addvars(data, repmat(fileTableID, height(data), 1), 'Before', 1, 'NewVariableNames', 'FileID');
end