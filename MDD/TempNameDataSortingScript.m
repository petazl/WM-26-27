files = dir('*.tdms');

% loadFile = tdmsread(files(1).name);
% dataInfo = tdmsinfo(files(1).name);
% 
% data = loadFile{1};
% 
% channellist = dataInfo.ChannelList;
% 
% % writetable(data, 'myTable.xlsx');
% 
% % writetable(channellist, 'myChannelList.xlsx');
% 
% % writetable(data, 'myFullTable.xlsx', 'Sheet', 1);
% % writetable(channellist, 'myFullTable.xlsx', 'Sheet', 2);
% 
% % excelData = readtable('myFullTable.xlsx', 'Sheet', 1);
% 
% % writetable(channellist, 'myFullTable.xlsx', 'Sheet', 2, WriteMode='append');
% 
% data = addvars(data, (1:height(data))','Before',1,'NewVariableNames','SampleID');
% 
% 
% % writetable(data,'test2.xlsx');
% 
% 
% loadFile2 = tdmsread(files(2).name);
% dataInfo2 = tdmsinfo(files(2).name);
% 
% data2 = loadFile{1};
% 
% channelList2 = dataInfo2.ChannelList;
% 
% fileNames = files.name;
% 
% tableOfFileNames = table({files.name}', 'VariableNames', {'FileName'});
% tableOfFileNames = addvars(tableOfFileNames, (1:height(files))','Before',1,'NewVariableNames','FileID');]


function fileTableCreated = createFileSheetTable(files)
    
    
    tableOfFileNames = table({files.name}', 'VariableNames', {'FileName'});
    tableOfFileNames = addvars(tableOfFileNames, (1:height(files))','Before',1,'NewVariableNames','FileID');
    fileTableCreated = tableOfFileNames;

end


function loadTdmsFileData(filename,fileTableID)
 
    loadFile = tdmsread(filename);
    
    data = loadFile{1};

    data = addvars(data, (1:height(data))','Before',1,'NewVariableNames','SampleID');

    data = addvars(data, repmat(fileTableID, height(data), 1), 'Before',1,'NewVariableNames','FileID');

    writetable(data,'MasterDataSheetTest.xlsx', 'Sheet', 3, 'WriteMode','append');

end
    
fileTable = readtable('MasterDataSheetTest.xlsx','Sheet',1);
% channelTable = readtable('MasterDataSheetTest.xlsx','Sheet',2);
% dataTable = readtable('MasterDataSheetTest.xlsx','Sheet',3);

latestFileId = fileTable{end,1};

% createFileTable = createFileSheetTable(files);
% writetable(createdFileTable, 'MasterDataSheetTest.xlsx', 'Sheet', 1, 'WriteMode','');
% 
% dataInfo = tdmsinfo(files(1).name);
% channellist = dataInfo.ChannelList;
% writetable(channellist, 'MasterDataSheetTest.xlsx', 'Sheet', 2, 'WriteMode','append');]

function appendToFileIDTable(filename, FileTableID)
    rowToBeAppended = table({filename}, 'VariableNames', {'FileName'});
    rowToBeAppended = addvars(rowToBeAppended, FileTableID,'Before',1,'NewVariableNames','FileID');

% Add some sort of input for a description of the file here. If needed, or
% add a description for the sheet

    writetable(rowToBeAppended, 'MasterDataSheetTest.xlsx', 'Sheet', 1, 'WriteMode', 'append');
end

for i = 1:height(files)
    if ismember(files(i).name, fileTable.FileName)
        fprintf('File %s already loaded\n', files(i).name);
    else
        % Old
        % loadTdmsFileData(files(i).name, createFileTable.FileID(i));

        % New
        appendToFileIDTable(files(i).name, (latestFileId + 1)); 
        loadTdmsFileData(files(i).name, (latestFileId + 1));
        fprintf('Attempting to load %s data... \n', files(i).name);
        latestFileID = latestFileId + 1;
        fprintf('File Data %s succesfully loaded\n', files(i).name); 
    end
end
    