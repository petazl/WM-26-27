updated ChannelSheetMDD:
- now includes voltage and current for phases 1-7 (last 13 rows)
- added descriptions where possible, will need verification
- added units where possible, will need verification
- description and unit columns are pulled from this document and used in the MDD

updated script:
- improved description sheet; syncs with ChannelSheetMDD (linked previous point above)
- added filtering logic for open circuit and short circuit folders as these have different file structures
- produced excel file is now called "MDD" instead of "MasterDataSheetTest"

things to note:
- the MDD output of the script is nearly 350Mb
- takes even longer to run now
- run same way as old one (in same directory as data folders)
- make sure to replace old ChannelSheetMDD with new one
