% Setup script directory
scriptFolder = fileparts(mfilename('fullpath'));
if isempty(scriptFolder)
    scriptFolder = pwd; 
end

% --- CHANNEL CONFIGURATION (NAME-BASED) ---
channelConfigFile = fullfile(scriptFolder, 'ChannelSheetMDD.xlsx');
channelConfig = readtable(channelConfigFile, 'Sheet', 1, 'TextType', 'string');

rawLog = channelConfig.LogThisChannel;
if isstring(rawLog) || iscellstr(rawLog)
    logMask = strcmpi(strtrim(string(rawLog)), "true") | strtrim(string(rawLog)) == "1";
else
    logMask = logical(rawLog);
end

allConfiguredNames = strtrim(string(channelConfig.Channel_Name));
allowedChannels = allConfiguredNames(logMask);
allowedChannels = setdiff(allowedChannels, ["FileID", "SampleID"], 'stable');

folderNames = {
    'Efficiency'
    'Open-circuit'
    'short-circuit'
    'torque-speed-envelope'
    };

outputFile = fullfile(scriptFolder, 'MDD.xlsx');

% --- CONSTANTS ---
EXCEL_ROW_LIMIT = 1048000;  % Buffer below Excel's 1,048,576 row limit
BUFFER_ROW_LIMIT = 1048000; % Hold up to a full sheet in RAM so each sheet writes once

% Initialize or read the existing File Index and Data Dictionary
if isfile(outputFile)
    fileTable = readtable(outputFile, 'Sheet', 'File Lookup');
    if isempty(fileTable)
        latestFileId = 0;
        existingFiles = strings(0, 1);
    else
        latestFileId = fileTable.FileID(end);
        existingFiles = string(fileTable.FileName);
    end
    
    try
        dictTable = readtable(outputFile, 'Sheet', 'Description', 'TextType', 'string');
        knownChannels = string(dictTable.Channel_Name)';
        
        for k = 1:height(dictTable)
            cfgIdx = find(allConfiguredNames == dictTable.Channel_Name(k), 1);
            if ~isempty(cfgIdx)
                if ismember("Description", channelConfig.Properties.VariableNames) && ~ismissing(channelConfig.Description(cfgIdx))
                    dictTable.Description(k) = string(channelConfig.Description(cfgIdx));
                end
                if ismember("Unit", channelConfig.Properties.VariableNames) && ~ismissing(channelConfig.Unit(cfgIdx))
                    dictTable.Unit(k) = string(channelConfig.Unit(cfgIdx));
                end
            end
        end
        writetable(dictTable, outputFile, 'Sheet', 'Description', 'WriteMode', 'overwritesheet');
    catch
        knownChannels = strings(1, 0);
    end
else
    disp('Initializing new workbook. Reserving File Lookup and Description sheets...');
    
    dummyIndex = cell2table(cell(0,2), 'VariableNames', {'FileID', 'FileName'});
    writetable(dummyIndex, outputFile, 'Sheet', 'File Lookup'); 
    
    dummyDict = cell2table(cell(0,3), 'VariableNames', {'Channel_Name', 'Description', 'Unit'});
    writetable(dummyDict, outputFile, 'Sheet', 'Description'); 
    
    latestFileId = 0;
    existingFiles = strings(0, 1);
    knownChannels = strings(1, 0);
end

% Loop through each folder
for i = 1:length(folderNames)
    testType = folderNames{i};
    currentFolderPath = fullfile(scriptFolder, testType);
    files = dir(fullfile(currentFolderPath, '**', '*.tdms'));
    
    if strlength(testType) > 24
        baseSheetName = char(extractBefore(string(testType), 25));
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
                testName = sprintf('%s_Part%d', baseSheetName, folderPartCounter);
            end
            
            try
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
    
    % Cell-based buffers avoid repeated memory reallocation while accumulating files
    bufferCells = {};
    indexBufferCells = {};
    bufferRowCount = 0;
    dictDataBuffer = table();
    
    for j = 1:length(files)
        currentFileName = files(j).name;
        filePath = fullfile(files(j).folder, currentFileName);
        
        if ismember(string(currentFileName), existingFiles)
            fprintf('File %s already loaded\n', currentFileName);
        else
            latestFileId = latestFileId + 1;
            
            fprintf('Loading %s into memory buffer... \n', currentFileName);
            newTableData = prepareTdmsData(filePath, latestFileId, allowedChannels);
            numRows = height(newTableData);
            
            % --- EXAMINE CHANNELS FOR DESCRIPTION SHEET ---
            currentVars = string(newTableData.Properties.VariableNames);
            newVars = setdiff(currentVars, knownChannels, 'stable');
            
            if ~isempty(newVars)
                knownChannels = [knownChannels, newVars];
                
                descCol = strings(length(newVars), 1);
                unitCol = strings(length(newVars), 1);
                for v = 1:length(newVars)
                    cfgIdx = find(allConfiguredNames == newVars(v), 1);
                    if ~isempty(cfgIdx)
                        if ismember("Description", channelConfig.Properties.VariableNames) && ~ismissing(channelConfig.Description(cfgIdx))
                            descCol(v) = string(channelConfig.Description(cfgIdx));
                        end
                        if ismember("Unit", channelConfig.Properties.VariableNames) && ~ismissing(channelConfig.Unit(cfgIdx))
                            unitCol(v) = string(channelConfig.Unit(cfgIdx));
                        end
                    end
                end
                
                newDictRows = table(newVars', descCol, unitCol, ...
                    'VariableNames', {'Channel_Name', 'Description', 'Unit'});
                dictDataBuffer = [dictDataBuffer; newDictRows];
            end
            
            % --- EXCEL LIMIT CHECK & OVERFLOW TRIGGER ---
            if (currentSheetRows + numRows) >= EXCEL_ROW_LIMIT
                if bufferRowCount > 0
                    fprintf('--> Sheet %s reached capacity (%d rows). Flushing to Excel...\n', currentSheetName, bufferRowCount);
                    flushBuffers(bufferCells, indexBufferCells, dictDataBuffer, outputFile, currentSheetName);
                    bufferCells = {};
                    indexBufferCells = {};
                    bufferRowCount = 0;
                    dictDataBuffer = table();
                end
                
                if folderPartCounter == 1
                    folderPartCounter = 2;
                end
                currentSheetName = sprintf('%s_Part%d', baseSheetName, folderPartCounter);
                folderPartCounter = folderPartCounter + 1;
                currentSheetRows = 1;
                
                fprintf('\n>>> CREATING OVERFLOW SHEET: %s <<<\n', currentSheetName);
            end
            
            % Stage into cell buffers (O(1) append, no large table copying)
            bufferCells{end+1} = newTableData;
            indexBufferCells{end+1} = table(latestFileId, {currentFileName}, 'VariableNames', {'FileID', 'FileName'});
            bufferRowCount = bufferRowCount + numRows;
            
            currentSheetRows = currentSheetRows + numRows;
            existingFiles(end+1) = string(currentFileName);
            
            % Flush if memory buffer hits limit
            if bufferRowCount >= BUFFER_ROW_LIMIT
                fprintf('--> Buffer reached %d rows. Flushing chunk to %s...\n', bufferRowCount, currentSheetName);
                flushBuffers(bufferCells, indexBufferCells, dictDataBuffer, outputFile, currentSheetName);
                bufferCells = {};
                indexBufferCells = {};
                bufferRowCount = 0;
                dictDataBuffer = table();
            end
        end
    end
    
    % End of folder: Flush remaining data
    if bufferRowCount > 0
        fprintf('--> Flushing final chunk (%d rows) for %s to %s...\n', bufferRowCount, testType, currentSheetName);
        flushBuffers(bufferCells, indexBufferCells, dictDataBuffer, outputFile, currentSheetName);
    end
end

disp('All TDMS files consolidated and processed successfully!');

%% --- LOCAL FUNCTIONS ---

function preparedData = prepareTdmsData(filepath, fileTableID, allowedChannels)
    loadFile = tdmsread(filepath);
    data = table();
    
    for k = 1:numel(loadFile)
        cellData = loadFile{k};
        
        if istimetable(cellData)
            cellData = timetable2table(cellData, 'ConvertRowTimes', false);
        elseif ~istable(cellData)
            cellData = array2table(cellData);
        end
        
        if isempty(cellData) || height(cellData) == 0 || width(cellData) == 0
            continue;
        end
        
        if isempty(data)
            data = cellData;
        elseif height(cellData) == height(data)
            dupCols = ismember(cellData.Properties.VariableNames, data.Properties.VariableNames);
            cellData(:, dupCols) = [];
            if width(cellData) > 0
                data = [data, cellData];
            end
        else
            fprintf('   [WARNING] Skipping TDMS group %d in %s (row count %d ~= %d)\n', ...
                k, filepath, height(cellData), height(data));
        end
    end
    
    tdmsVars = strtrim(string(data.Properties.VariableNames));
    keepMask = ismember(tdmsVars, allowedChannels);
    data = data(:, keepMask);
    
    data = addvars(data, (1:height(data))', ...
        'Before', 1, 'NewVariableNames', 'SampleID');
    preparedData = addvars(data, ...
        repmat(fileTableID, height(data), 1), ...
        'Before', 1, 'NewVariableNames', 'FileID');
end

function flushBuffers(bufferCells, indexBufferCells, dictDataBuffer, outputFile, sheetName)
    % Single-pass column alignment and vertical concatenation
    allVars = {};
    for k = 1:numel(bufferCells)
        allVars = [allVars, setdiff(bufferCells{k}.Properties.VariableNames, allVars, 'stable')]; %#ok<AGROW>
    end
    
    for k = 1:numel(bufferCells)
        missingVars = setdiff(allVars, bufferCells{k}.Properties.VariableNames, 'stable');
        for m = 1:numel(missingVars)
            bufferCells{k}.(missingVars{m}) = repmat(missing, height(bufferCells{k}), 1);
        end
        bufferCells{k} = bufferCells{k}(:, allVars);
    end
    
    mergedData = vertcat(bufferCells{:});
    mergedIndex = vertcat(indexBufferCells{:});
    
    writetable(mergedData, outputFile, 'Sheet', sheetName, 'WriteMode', 'append');
    writetable(mergedIndex, outputFile, 'Sheet', 'File Lookup', 'WriteMode', 'append');
    
    if ~isempty(dictDataBuffer)
        writetable(dictDataBuffer, outputFile, 'Sheet', 'Description', 'WriteMode', 'append');
    end
end