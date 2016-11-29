@{
#-- CSV migratie file
CSVfile=$scriptpath.fullname+"\migratie.csv"
CSV_Delimiter=";"
#CSVfile=$scriptpath.fullname+"\proef.csv"

#-- Maximum active Robocopy jobs
Max_Active_RC_jobs=10
SleepMonnitorLoop=5 #-- amount of seconds the job loop waits in each loop. 
RC_Logpath=$log.location  #--Log path for robocopy logs, log object is initiated  in the initialization fase

#-- Tijdsinterval voor loggen van de voortgang
ProgressInterval="00:05:00"

#-- Volg de ingestelde run tijden
ObeyRunningSchedule=$false 

#-- throttling parameters voor Robocopy. Wanneer één van de velden geen logische waarde heeft, wordt throttling genegeerd
DesiredBandwith=250000   #--Bd [kbps] 
AvailableBandwith=1000000   #--Ba [Kbps]
setIPG=$true
IPG=4 #-- [ms]  

<#
IPG = 512000*(Ba-Bd)/(Ba*Bd)
IPG tabel
IPG		1		100
		Gbps	Mbps
[ms]	[%]		[%]
0		100		100
1		34		84
2		20		72
3		15		63
4		11		56
5		9		51
6		8		46
7		7		42
8		6		39
9		5		36
10		5		34
11		4		32
12		4		30
13		4		28
14		4		27
15		3		25
#>

#-- Robocopy parameters
RC_Param_main="/W:5 /R:3 /ZB /NP /PURGE /COPYALL /L /v"
RC_Param_sub="/W:5 /R:3 /ZB /NP /MIR /COPYALL /L /v"

<#
Robocopy parameters explained

                /Z : Copy files in restartable mode (survive network glitch).
                /B : Copy files in Backup mode.
               /ZB : Use restartable mode; if access denied use Backup mode.
              /R:n : Number of Retries on failed copies - default is 1 million.
              /W:n : Wait time between retries - default is 30 seconds.
            /PURGE : Delete dest files/folders that no longer exist in source.
              /MIR : MIRror a directory tree - equivalent to /PURGE plus all subfolders (/E)
                /L : List only - donâ€™t copy, timestamp or delete any files.
               /NP : No Progress - donâ€™t display % copied.
         /LOG:file : Output status to LOG file (overwrite existing log).
              /NDL : No Directory List - donâ€™t log directory names.
           /SECFIX : FIX file SECurity on all files, even skipped files.	
		  /COPYALL : Copy ALL file info (equivalent to /COPY:DATSOU).
/XD dirs [dirs]... : eXclude Directories matching given names/paths.
                /v : log verbose		  
#>

#-- Periods when script is not allowed to run
BlockedPeriods=@(
    @{Day       = "weekday"   #-- valid options are weekday,weekend,,Monday,Tuesday,Wednesday,Thursday,Friday,Saturday,Sunday
      StartTime = "07:00:00"  #- use 24 hr notation incl. leading zero's
      endTime   = "19:00:00"}
      )
}