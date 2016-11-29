<#
.SYNOPSIS
    Mirror folders between two file servers, using Robocopy.
.DESCRIPTION
    Mirror folders between two CIFS file servers, using Robocopy.
    The source and destination folders are given in a CSV file. (source and destination shares can be different)
    A seperate Robocopy job will be generated for each folder and its subfolder (1 level down)
    These jobs wil run in seperate threads with a set maximum of threads executing parallel.

    A file with parameters and a CSV file is needed to run this function.
    Both need to be in the same folder as this script.
    Parameters are placed in the file parameters.ps1
    The CSV must have the semicolon as a delimiter (easier to edit with Excel)
.EXAMPLE
    >Mirror-CIFS
.NOTES
    File Name      : Mirror-CIFS.ps1
    Author         : B. Lievers
    Prerequisite   : PowerShell V2 over Vista and upper.
    Copyright 2015 - Bart Lievers
#>
[CmdletBinding()]

Param()

begin{

    #region Private functions

    function calc-IPG {
        <#
        .SYNOPSIS
            Calculate IPG [ms] parameter for Robocopy
        .EXAMPLE
            >$IPG=calc-ipg -Ba 1000000 -Bd 250000
            Calculate IPG with an available bandwith of 1.000.000 kbps (1Gbps) and a desired bandwith of 250.000 kbps
        .PARAMETER Ba [kbps]
            Available bandwith
        .PARAMETER Bd [kbps]
            Desired bandwith
        .PARAMETER nT
            Number of multiple threads to run Robocopy with.
        #>
        Param (
        [int]$Ba, #-- Available bandwith
        [Int]$Bd,  #-- desired bandwith
        [int]$nT #-- number of Threads
        )
        if ($nT -eq 0) {$nt =1}
        $answer=($Ba-($Bd/$nT))*512*1000/($Ba*($Bd/$nT))
        $answer=[decimal]::round($answer)
        Return ($answer)
    }

    function calc-Bd {
        <#
        .SYNOPSIS
            Calculate desired bandwith with a given IPG
        .EXAMPLE
            >$Bd=calc-Bd -D 4 -Ba 1.000.000 -Perc
            Calculates the desired bandwith with a given IPG in percentage
        .PARAMETER Ba [kpbs]
            Available bandwith
        .PARAMETER D [ms]
            Delay between packets, IPG in ms
        .PARAMETER perc
            [switch] answer in percentage of Ba
        #>
        Param (
        [switch]$Perc, #-- return desired bandwith as a percentage of available
        [int]$Ba,      #-- [kbps] available bandwith
        [int]$D        #-- [ms] IPG
        )
    
        $Bd=(512000*$Ba)/($Ba*$d+512000)
        if ($Perc) {
            Return([decimal]::round(100*$Bd/$Ba))
        } else {
            Return([decimal]::round($Bd))
        }
    }

    function New-TimeStamp {
        <#
        .SYNOPSIS
            Returns a timestamp based on currente date and time
        .EXAMPLE
            >$TS=New-TimeStamp -serial -sortable -noseconds
            returns the current date and time (p.e. 8 mar 2015 16:03:45 as 20150308160345
        .PARAMETER serial
            Removes all seperators including spaces.
        .PARAMETER -sortable
            Returns a sortable timestamp in yyyyMMddHHmmss
        .PARAMETER -noseconds
            skips the seconds
        #>
	    [cmdletbinding()]
	    param(
		    [switch]$Sortable,
		    [switch]$serial,
		    [switch]$noSeconds
		    )
		    $TimeFormat="%H:%M:%S"
		    if ($Sortable) {
			    $TimeFormat="%Y-%m-%d-%H:%M:%S"
		    } else {
			    $TimeFormat="%d-%m-%Y-%H:%M:%S"	
		    }
		    if($serial){
			    $TimeFormat=$TimeFormat.replace(":","").replace("-","")
		    }
		    if ($noSeconds) {
			    $TimeFormat=$TimeFormat.replace(":%S","").replace("%S","")
			
		    }
		    return (Get-Date -UFormat $TimeFormat)		
    }

    Function Write-Log {
	    <#
	    .SYNOPSIS  
	        Write message to logfile   
	    .DESCRIPTION 
	        Write message to logfile and associated output stream (error, warning, verbose etc...)
		    Each line in the logfile starts with a timestamp and loglevel indication.
		    The output to the different streams don't contain these prefixes.
		    The message is always sent to the verbose stream.
	    .NOTES  
	        Author         : Bart Lievers
	        Copyright 2013 - Bart Lievers 
	    .PARAMETER LogFilePath
		    The fullpath to the log file
	    .PARAMETER message
		    The message to log. It can be a multiline message
	    .Parameter NoTimeStamp
		    don't add a timestamp to the message
	    .PARAMETER isWarning
		    The message is a warning, it will be send to the warning stream
	    .PARAMETER isError
		    The message is an error message, it will be send to the error stream
	    .PARAMETER isDebug
		    The message is a debug message, it will be send to the debug stream.
	    .PARAMETER Emptyline
		    write an empty line to the logfile.
	    .PARAMETER toHost
		    write output also to host, when it has no level indication
	    #>	
	    [cmdletbinding()]
	    Param(
		    [Parameter(helpmessage="Location of logfile.",
					    Mandatory=$false,
					    position=1)]
		    [string]$LogFile=$LogFilePath,
		    [Parameter(helpmessage="Message to log.",
					    Mandatory=$false,
					    ValueFromPipeline = $true,
					    position=0)]
		    $message,
		    [Parameter(helpmessage="Log without timestamp.",
					    Mandatory=$false,
					    position=2)]
		    [switch]$NoTimeStamp,
		    [Parameter(helpmessage="Messagelevel is [warning.]",
					    Mandatory=$false,
					    position=3)]
		    [switch]$isWarning,
		    [Parameter(helpmessage="Messagelevel is [error]",
					    Mandatory=$false,
					    position=4)]
		    [switch]$isError,
		    [Parameter(helpmessage="Messagelevel is [Debug]",
					    Mandatory=$false,
					    position=5)]
		    [switch]$isDebug,
		    [Parameter(helpmessage="Messagelevel is [Verbose]",
					    Mandatory=$false,
					    position=5)]
		    [switch]$isVerbose,
		    [Parameter(helpmessage="Write an empty line",
					    Mandatory=$false,
					    position=6)]
		    [switch]$EmptyLine
	    )
	    # Prepare the prefix
	    [string]$prefix=""
	    if ($isError) {$prefix ="[Error]       "}
	    elseif ($iswarning) {$prefix ="[Warning]     "}
	    elseif ($isDebug) {$prefix="[Debug]       "}
	    elseif ($isVerbose) {$prefix="[Verbose]     "}
	    else {$prefix ="[Information] "}
	    if (!($NoTimeStamp)) {
			    $prefix = ((new-TimeStamp) + " $prefix")}
	    if($EmptyLine) {
		    $msg =$prefix
	    } else {
		    $msg=$prefix+$message}
	    #-- handle multiple lines
	    $msg=[regex]::replace($msg, "`n`r","", "Singleline") #-- remove multiple blank lines
	    $msg=[regex]::Replace($msg, "`n", "`n"+$Prefix, "Singleline") #-- insert prefix in each line
	    #-- write message to logfile, if possible
	    if ($LogFile.length -gt 0) {
		    if (Test-Path $LogFile) {
			    $msg | Out-File -FilePath $LogFile -Append -Width $msg.length } 
		    else { Write-Warning "Geen geldig log bestand opgegeven (`$LogFilePath). Er wordt niet gelogd."}
	    } 
	    else {
		    Write-Warning "Geen geldig log bestand opgegeven (`$LogFilePath). Er wordt niet gelogd."
	    } 
	    #-- write message also to designated stream
	    if ($isError) {Write-Error $message}
	    elseif ($iswarning) {Write-Warning $message}
	    elseif ($isDebug) {Write-Debug $message}
	    elseif ($isVerbose) {Write-Verbose $message}
	    else {Write-output $message}
    } 

    Function New-LogObject {
	    <#
	    .SYNOPSIS  
	        Creating a text log file. Returning an object with methods to ad to the log     
	    .DESCRIPTION  
		    The function creates a new text file for logging. It returns an object with properties about the log file.	
		    and methods of adding logs entry
	    .NOTES  
	        Author         : Bart Lievers
	        Copyright 2013 - Bart Lievers   	
	    #>
	    [cmdletbinding()]
	    param(
	    [Parameter(Mandatory=$true,
		    helpmessage="The name of the eventlog to grab or create.")][string]$name,
	    [Parameter(Mandatory=$true,
		    helpmessage="Add a timestamp to the name of the logfile")][switch]$TimeStampLog,		
	    [Parameter(Mandatory=$false,
		    helpmessage="Location of log file. Default the %temp% folder.")]
		    [string]$location=$env:temp,	
	    [Parameter(Mandatory=$false,
		    helpmessage="File extension to be used. Default is .log")]
		    $extension=".log"
	    )
	    Write-Verbose "Input parameters"
	    Write-Verbose "`$name:$name"
	    Write-Verbose "`$location:$location"
	    Write-Verbose "`$extension:$extension"
	    if ($TimeStampLog) {
		    $Filename=((new-timestamp -serial -sortable -noSeconds )+"_"+$name+$extension)
	    } else {		
		    $Filename=$name+$extension
	    }
	    $FullFilename=$location + "\" +  $filename
	    if (!(Test-Path -IsValid $FullFilename)) {Write-Warning "Opgegeven naam en/of location zijn niet correct. $FullFilename"; exit}
	
	    $obj = New-Object psobject
	    $obj | Add-Member -MemberType NoteProperty -Name file -Value $FullFilename -PassThru |
	    Add-Member -MemberType NoteProperty -Name Name -Value $name -PassThru |
	    Add-Member -MemberType NoteProperty -Name Location -Value $location -PassThru |
	    Add-Member -MemberType ScriptMethod -Name write -Value {
		    param(
			    [string]$message
		    )
		    if (!($message)) {Out-File -FilePath $this.file -Append -InputObject ""} Else {
		    Out-File -FilePath $this.file -Append -Width $message.length -InputObject $message}
	    } -PassThru |
	    Add-Member -MemberType ScriptMethod -Name create -value {
		    Out-File -FilePath $this.file -InputObject "======================================================================"
		    $this.write("")
		    $this.write("         name : "+ $this.name)		
		    $this.write("	  log file : " + $this.file)
		    $this.write("	created on : {0:dd-MMM-yyy hh:mm:ss}" -f (Get-Date))
		    $this.write("======================================================================")
	    } -PassThru |
	    Add-Member -MemberType ScriptMethod -Name remove -value {
		    if (Test-Path $this.file) {Remove-Item $this.file}
	    } -PassThru |
	    add-member -MemberType ScriptMethod -Name msg -Value {
		    param(
			    [string]$message
		    )	
		    if ((Test-Path $this.file) -eq $false) { $this.create()}
		    Write-Log -LogFile $this.file -message $message
	    } -PassThru  |
	    add-member -MemberType ScriptMethod -Name warning -Value {
		    param(
			    [string]$message
		    )	
		    if ((Test-Path $this.file) -eq $false) { $this.create()}	
		    Write-Log -LogFile $this.file -message $message -isWarning
	    } -PassThru  |
	    add-member -MemberType ScriptMethod -Name debug -Value {
		    param(
			    [string]$message
		    )	
		    if ((Test-Path $this.file) -eq $false) { $this.create()}	
		    Write-Log -LogFile $this.file -message $message -isDebug
	    } -PassThru  |
	    add-member -MemberType ScriptMethod -Name error -Value {
		    param(
			    [string]$message
		    )		
		    if ((Test-Path $this.file) -eq $false) { $this.create()}
		    Write-Log -LogFile $this.file -message $message -isError
	    } -PassThru   |
	    add-member -MemberType ScriptMethod -Name verbose -Value {
		    param(
			    [string]$message
		    )	
		    if ((Test-Path $this.file) -eq $false) { $this.create()}	
		    Write-Log -LogFile $this.file -message $message -isVerbose
	    } -PassThru  |
	    add-member -MemberType ScriptMethod -Name emptyline -Value {
		    param(
			    [string]$message
		    )	
		    if ((Test-Path $this.file) -eq $false) { $this.create()}	
		    Write-Log -LogFile $this.file  -EmptyLine
	    } -PassThru | Out-Null 	
	    $obj.create() |out-null
	    Return $obj
    }

    Function get-Runningclearance {
        <#
        .SYNOPSIS
            Failsave to determine is script is allowed to run
            Returns True or False, according to time of day.
        .EXAMPLE
            >if (get-RunningClearance) {write-host allowed to run}
        .PARAMETER Periods
            Hashtable of periods in the format like
            @{
                @{Day       = "weekday"   #-- valid options are weekday,weekend,,Monday,Tuesday,Wednesday,Thursday,Friday,Saturday,Sunday
                StartTime = "07:00:00"  #- use 24 hr notation incl. leading zero's
                endTime   = "19:00:00"},
                @{Day       = "sunday"   #-- valid options are weekday,weekend,,Monday,Tuesday,Wednesday,Thursday,Friday,Saturday,Sunday
                StartTime = "13:00:00"  #- use 24 hr notation incl. leading zero's
                endTime   = "19:00:00"}
            }
        #>
        [cmdletbinding()]
        Param(
            $Periods
        )
        $notallowed=$false #-- we are allowed to run unless.....
        if ($Periods.count -gt 0){
            $Periods.GetEnumerator() | %{
                $Period=$_
                #-- check if Today is in the list
                switch ($Period.day) {
                    "weekday" {$day=(get-date).DayOfWeek -match "Monday|Tuesday|Wednesday|Thursday|Friday"}
                    "weekend" {$day=(get-date).DayOfWeek -match "Saturday|Sunday"}
                    default {$day=(get-date).DayOfWeek -match $Period.day}
                }
                $starttime=[timespan]$Period.starttime
                $Endtime=[timespan]$Period.Endtime
                #-- take care if endtime is smaller then starttime
                if ($endtime -lt $starttime) {$Endtime=$endtime.Add([timespan]"01:00:00:00")}
                $TOD=(get-date).TimeOfDay
                #-- check if current time is between start and end time
                $time=(($TOD -gt $starttime) -AND ($TOD -lt $Endtime))
                #-- are we in a blocked period ??
                $notAllowed=($day -and $time) -or $notallowed
            }
        }
        return ( !$notallowed  )
    }
    #endregion functions

                                                                                                                #region Script Initialization
	#-- determine path of script and name of script
	$scriptpath=get-item (Split-Path -parent $MyInvocation.MyCommand.Definition)
	$scriptname=Split-Path -Leaf $MyInvocation.mycommand.path
    #-- define logfile name
	if ($scriptname.Length -gt 0) { 
			$logname=$scriptname.Substring(0,$scriptname.indexof(".ps1"))
		}
		else {
			$logname="untitled"
		}

	#-- check for log folder
    
	$logdir=($scriptpath.fullname+"\Log\"+ (New-TimeStamp -Sortable -serial -noseconds)  )
	if ((Test-Path (Split-Path -Path $logdir -parent) ) -eq $false ) {
        #-- create log folder
		New-Item -Name (split-path -path (Split-Path -Path $logdir -parent) -leaf ) -Path $scriptpath.fullname -ItemType directory 
	}
	if ((Test-Path $logdir) -eq $false ) {
        #-- create log folder
		$logdir=New-Item -Name (split-path -path $logdir -leaf ) -Path (split-path -path $logdir -parent ) -ItemType directory 
	}    
	#-- create log
	$global:log=New-LogObject -name $logname -location $logdir -TimeStampLog
	Write-Host ("Log file : "+ $log.file+ "`n")

    #-- load parameters from file
    $P= & ($scriptpath.fullname+"\parameters.ps1") 
    #endregion initialisations


    #-- Calculate IPG

    #-- calculate bandwith parameter, if needed
    if (($P.AvailableBandwith -gt 0 ) -and ($P.DesiredBandwith -gt 0) -and ($P.DesiredBandwith -le $P.AvailableBandwith)) {
        $log.msg("Bandwith throthling voor robocopy.")
        if ($P.max_active_RC_jobs -gt $Hash_rcjobs.count) {
            $RC_IPG=calc-IPG -Ba $P.availablebandwith -Bd $P.DesiredBandwith -nT $Hash_rcjobs.count   
        } else {
            $RC_IPG=calc-IPG -Ba $P.availablebandwith -Bd $P.DesiredBandwith -nT $P.Max_Active_RC_jobs
        }
        if ($P.setIPG) {
            $RC_IPG=$P.ipg
        }
        $log.verbose("Robocopy Inter Packet Gap (/IPG) [ms]:" + $RC_IPG + " == "+ (calc-bd -Ba $P.availablebandwith -D $RC_IPG -perc ) + " % of available Bandwith")
        $P.RC_Param_main= $P.RC_Param_main + " /IPG:"+ $RC_IPG
        $log.verbose("Robocopy parameters voor hoofdfolders gewijzigd naar: "+$P.RC_Param_main)    
        $P.RC_Param_sub= $P.RC_Param_sub + " /IPG:"+ $RC_IPG
        $log.verbose("Robocopy parameters voor subfolders gewijzigd naar: "+$P.RC_Param_sub)
    } else {
        $log.msg("Geen bandwith throthling voor robocopy.")
    }
}

Process{

    #-- Mark start of script
    $TS_StartScript=get-date
    $log.msg("Start script $TS_StartScript")


    $log.verbose("Parameters :")
    $log.verbose("CSVfle                                : "+$P.csvfile)
    $log.verbose("Max. aantal RC jobs / threads         : "+$P.Max_Active_RC_jobs)
    $log.verbose("Monitor cyclus slaap tijd `[s`]         : "+$P.SleepMonnitorLoop)
    $log.verbose("Robocopy logs folder                  : "+$P.RC_Logpath)
    $log.verbose("Robocopy parameters voor hoofdfolders : "+$P.RC_Param_main)
    $log.verbose("Robocopy parameters voor subfolders   : "+$P.RC_Param_sub)
    $log.verbose("Voortgangs rapportage interval        : "+$P.ProgressInterval)
    $log.verbose("Gewenste bandbreedte           [kBps] : "+$P.DesiredBandwith)
    $log.verbose("Beschikbare bandbreedte        [kBps] : "+$P.AvailableBandwith)

    #region Import and process CSV file
    #-- import the CSV file with the folders to migrate
    if (!(Test-Path -Path $P.csvfile)) {
        $log.warning($P.csvfile + " bestaat niet.")
        EXIT
    }
    $MigFolders=Import-Csv $P.csvfile -Delimiter $P.CSV_Delimiter

    #-- add some fields to it
    $MigFolders |  Add-Member -MemberType NoteProperty -Name CIFSShare -Value ""
    $MigFolders |  Add-Member -MemberType NoteProperty -Name ParentFolder -Value ""
    $MigFolders |  Add-Member -MemberType NoteProperty -Name DstShare -Value ""
    $MigFolders |  Add-Member -MemberType NoteProperty -Name SrcShare -Value ""
    #-- Check if CSV file has correct headers
    $CorrectHeaders=$true
  #  if (!($MigFolders |GM  -MemberType NoteProperty | ?{$_.name -match "Map"})) {$CorrectHeaders=$false}
    if (!($MigFolders |GM  -MemberType NoteProperty | ?{$_.name -match "Dst"})) {$CorrectHeaders=$false}
    if (!($MigFolders |GM  -MemberType NoteProperty | ?{$_.name -match "Src"})) {$CorrectHeaders=$false}
    if (!($MigFolders |GM  -MemberType NoteProperty | ?{$_.name -match "DSTFiler"})) {$CorrectHeaders=$false}
    if (!($MigFolders |GM  -MemberType NoteProperty | ?{$_.name -match "SRCFiler"})) {$CorrectHeaders=$false}
    if (!($MigFolders |GM  -MemberType NoteProperty | ?{$_.name -match "Exclude"})) {$CorrectHeaders=$false}
    if ($CorrectHeaders -eq $false) {
	    log.warning("$P.csvfile heeft niet de correcte headers. `n Deze moeten zijn src;dst;DSTFiler;SRCFiler;Exclude.`n Het scheidingsteken is de ; `N Einde script.")
	    EXIT
	    }	

    #-- process the CSV table
    $MigFolders |  %{ #-- walk through the array
    # Find the path
	    #-- clear, if necessary, a trailing \ and/or spaces
	    $_.dst=$_.dst.trimend("\ ")
	    $_.src=$_.src.trimend("\ ")
        #-- copy src to dst when no dst is given.
        if ($_.dst -eq "" ) { $_.dst=$_.src}
        #-- get the destination share and the source share
        $isRootfolder=$_.src.indexof("\",1) -eq -1      
	    if ( $isRootfolder) { #-- given path is a root folder or CIFS share
            if ($_.src.substring(0,1) -eq "\") {
                $_.SRCshare=$_.src.substring(1)
            } else {
                $_.SRCshare=$_.src
                $_.src="\"+$_.src    
            }
            if ($_.dst.substring(0,1) -eq "\") {
                $_.dstshare=$_.dst.substring(1)
            } else {
                $_.dstshare=$_.dst
                $_.src="\"+$_.src    
            }
	    }  else { #-- given path is not a root folder or CIFS share
            if ($_.src.substring(0,1) -eq "\") {
                $_.SRCshare=$_.src.substring(1,$_.src.indexof("\",1)-1)
            } else {
                $_.SRCshare=$_.src.substring(0,$_.src.indexof("\",1))
            }    

            if ($_.dst.substring(0,1) -eq "\") {
                $_.dstshare=$_.dst.substring(1,$_.dst.indexof("\",1)-1)
            } else {
                $_.dstshare=$_.dst.substring(0,$_.dst.indexof("\",1))
            }    
	    }
        #-- determine parent path of source path
	    $pos=0
	    while ( $pos -ge 0 )  {
		    $lastpos=$pos
		    $pos=$_.src.indexof("\",$lastpos+1 )
	    }
	    if ($lastpos -eq 0)  {
		    $_.Parentfolder="\"}
	    else {
		    $_.ParentFolder=$_.src.substring(0,$lastpos)
	    }
	
    } 

    #-- build some hash tables for easy searches
    $Hash_Migfolders=@{}
    $MigFolders | %{
	    $Hash_Migfolders.add($_.src,$_)
    }
    #endregion

    #region Build list of folders to mirror
    #-- Scan All folders and build list of Robocopy folders. Each subfolder of a folder in the CSV is a seperate RC task
    $RCJobs=@()
    $log.verbose("Verzamelen van folders en subfolders voor robocopy opdrachten.")
    $Hash_rcjobs=@{} #-- for easy searching
    $MigFolders | %{
	    $folder=$_	
	    #-- first save the root folder
	    if (($folder.exclude -ilike "true") -eq $false) {
		    if ((Test-Path -path ("`\`\"+$folder.srcfiler+$folder.src)) -and (test-path -path ("`\`\"+$folder.DSTFiler+"\"+$folder.dstshare))) {	#-- make sure the root folders exist	
			    $tmpRecord= "" | select-object Source,Target,isRoot,folder,RCcmd
			    $tmpRecord.source= "`\`\"+ $folder.srcfiler + $_.src 
			    $tmpRecord.Target= "`\`\"+ $folder.dstfiler + $_.dst
			    $tmpRecord.folder=$_.src
			    $tmpRecord.isroot= $true
			    $RCJobs += $tmpRecord #-- add record to the array
			    $Hash_RCjobs.add($tmprecord.folder,$tmprecord) #-- and to the hash table
			
			    #-- get the subfolders in the rootfolder
			    $temp = @(Get-ChildItem -path ("`\`\"+$folder.srcfiler+$folder.src))
			    $temp | ? {$_.mode -ilike "d*"} | %{ #-- select only folders
				    $UNC_subfolder=$_.fullname
				    $subfolder=$UNC_subfolder.substring($UNC_subfolder.indexof("\",3))
                    $tmp=$subfolder.split("\")
                    $tmp[1]=$folder.DstShare
                    $subfolder=$tmp -join "\"
				    #--test if subfolder needs to be exluded
				    if ( $Hash_Migfolders.ContainsKey($subfolder) -eq $false	) { #-- don't add folder if we already know it
					    #-- add subfolder to joblist
					    $tmpRecord= "" | select-object Source,Target,isRoot,folder,RCcmd
					    $tmpRecord.source=  $UNC_subfolder
					    $tmpRecord.folder=  $subfolder
					    $tmpRecord.Target= "\\"+ $folder.dstfiler + $subfolder
					    $tmpRecord.isroot= $false
					    $RCJobs += $tmpRecord	#-- add record to the array	
					    $Hash_RCjobs.add($tmprecord.folder,$tmprecord) #-- and to the hash table
				    }
			    }
		    } elseif (Test-Path -path ("`\`\"+$folder.srcfiler+$folder.src)) {
			    $log.warning(("`\`\"+$folder.srcfiler+$folder.src) + " niet gevonden.")
		    } elseif (test-path -path ("`\`\"+$folder.DSTFiler+"\"+$folder.dstshare)) {
			    $log.warning(("`\`\"+$folder.DSTFiler+$folder.dstshare) + " niet gevonden.")
		    }
	    }
    }

    #-- the RC job list is finished.
    Write-Host ("We have "+ $Hash_rcjobs.count + " Robocopy jobs waiting.")
    $log.msg("Aantal unieke robocopy opdrachten : " + $Hash_rcjobs.count)
    #endregion



    #region Construct Robocopy commands ready to use in scriptblocks

    #-- construct the Robocopy command
    $TimeSerial=new-timestamp -serial -Sortable -noSeconds
    #-- replace spaces by a comma and add quotations marks around each robocopy parameter
    $P.RC_Param_sub="`""+$P.RC_Param_sub.Replace(" ","`",`"")+"`""
    $P.RC_Param_main="`""+$P.RC_Param_main.Replace(" ","`",`"")+"`""
    $RCJobs | %{ 
	    #-- the file name for the log file is the base path.
	    [string]$ROBOCOPYLOG="/LOG+:`"" + $P.RC_Logpath +"\RC_" + $_.folder.replace("\","_").substring(1).replace("$","") + "-" + $TimeSerial + ".log`""
	    $RCSOURCE=$_.source
	    $RCTARGET=$_.target
	    if ($_.isroot) { 
		    #-- if this folder is listed in the CSV, only copy it's content without subfolders.
		    [string]$_.Rccmd="& robocopy.exe `"$RCSOURCE`",`"$RCTARGET`","+$P.RC_Param_main+" $ROBOCOPYLOG";
		
		    }
	    else  { 
		    #-- if this folder is a result of the scan, mirror it (copy including with subfolders)
		    [string]$_.Rccmd="& robocopy.exe `"$RCSOURCE`",`"$RCTARGET`","+$P.RC_Param_sub+" $ROBOCOPYLOG";
		    }
    }
    #endregion


    #-- Initialise stuff for multithreading
    #-- create a worklist

    #region create runspace pool
    # Create a runspace pool
    #-- #Max_Active_RC_jobs is the max active jobs/runspaces in the pool.
    $pool = [RunspaceFactory]::CreateRunspacePool(1, $P.Max_Active_RC_jobs)
    $pool.ThreadOptions = "ReuseThread"
    $pool.ApartmentState = "STA"
    $pool.Open()

    #endregion 

    #region spawn the robocopy commands in runspaces and store it in a tasks list.
    # Iterate each object.  Create a pipeline and pass each object to the script block in the pipeline    
    # save it in a $task hashtable
    $tasks=@{}
    $i=0
    $TS_Report=get-date
    $TS_StartRCtasks=get-date
    $rcjobs| %{ #-- walkthrough the Robocopy array
	    $i++ #-- create a new ID
	    $tmpObj="" | select-object  Pipeline,Job,Handle,id,name,cmd #-- define template
	    $tmpObj.name = $_.folder.replace("\","_").substring(1) #-- name of the job is the path to copy
	    $tmpObj.cmd=$_.rccmd #-- store the constructed robocopy command
	    $tmpObj.id=$i #-- store the id
	    $tmpObj.Pipeline=[System.Management.Automation.PowerShell]::create()
	    $tmpObj.pipeline.RunspacePool = $pool #-- assign runspace to pool
	    $tmpObj.pipeline.AddScript([scriptblock]::Create($_.rccmd)) | Out-Null
   	    $tmpObj.Job=$tmpObj.pipeline.beginInvoke() #-- Invoke the robocopy command asynchronously (meaning it starts when there is room, runspaces open.)
	    $tmpObj.Handle=$tmpObj.Job.AsyncWaitHandle #-- store the handle
	    $tasks.Add($i,$tmpObj) #-- add it to the Tasks hashtable
	    }
    $Total=$tasks.count

    $log.msg("$Total taken in de rij gezet")
    #endregion
try
{
    #region Manage Runspaces
    #-- Run Monitor loop
    $TasksFailed=0
    $TasksFinished=0
    $exitloop=$false
    if ((get-Runningclearance -Periods $P.BlockedPeriods ) -eq $false) {
        $log.warning("Script mag niet draaien opdit tijdstip.")
        $exitloop=$true
    }
    While ($exitloop -eq $false) {	
	    if ( ((get-date)-$TS_Report) -gt $P.ProgressInterval) {
		    $temp=(Get-Date)-$TS_Report
		    $TasksFinishedpMin=[Math]::Round($TaskFinished/$temp.totalMinutes,1)
		    $log.verbose("--- " + ($tasks.count.tostring()) + " : actief -- " + $TasksFinished + ": Uitgevoerd --" + $TasksFailed + " : mislukt -- " + $TasksFinishedpMin + " : Uitgevoerd [/min] -- ")
		    $TS_Report=get-date
		    }
	    $Tasks2Remove=@() #-- Maintenance array of $task id's to remove
	    $tasks.GetEnumerator() | %{ #-- walk through the task list
		    $task=$_.value #-- current task to evaluate
		    try {
			    #if ($task.handle.waitone()) { #-- check if task is finished
			    if ($task.job.iscompleted) { #-- check if task is finished
				    $result=$task.pipeline.EndInvoke($task.job) #-- get results from finished task
				    $log.msg("RC opdracht "+ $task.name + " is uitgevoerd.")
				    $log.verbose($result)
				    $TasksFinished++
				    $task.pipeline.dispose() #-- $clean up the pipeline
				    $Tasks2Remove += $task.id #-- list task to be removed				
			    }
		    }
		    catch 
		    {  			
			    $log.warning("Robocopy opdracht voor "+$task.name + " is mislukt.") 
			    $log.warning($_)
			    $task.pipeline.dispose()			
			    $TasksFailed++
			    $Tasks2Remove += $task.id #-- list task to be removed
		    }	
	    }
	    #-- cleanup task table
	    $Tasks2Remove | %{
		    $tasks.Remove($_)
	    }
	    #-- let's not over do it, easy easy
	    Start-Sleep -Seconds $P.SleepMonnitorLoop
	    #-- Are we still alowed to run
	    $StopLoop=((get-Runningclearance -Periods $P.BlockedPeriods) -eq $false)
	    #-- update loop parameter, only run if there are stil tasks or we are not allowed to run anymore.
        if (test-path -path ($scriptpath.FullName+"\stop.txt") -PathType Leaf) {throw ($scriptpath.FullName+"\stop.txt gevonden. einde script.")}#-- we also stop when a file stop.txt is present
        if($StopLoop) { throw "Stopping jobs, not allowed to run at this time."} #-- throw an error
	    $exitloop=($Tasks.Count -le 0) -OR $StopLoop 
    }  #-- end of monitor loop
    #endregion

}
catch{
    #-- write the error to the log
    $log.warning($_)
}
 finally {
    #-- always cleanup the runspace.
    $log.verbose("cleaning up runspace pool.")
    #region cleanup pool and close
    #-- If we exited the monitor loop because we ran out of time, stop all $tasks.
    if ($StopLoop) {
	    #-- stop all tasks that are still in the list.
	    $log.warning($tasks.count.tostring() + " taken voortijdig gestopt vanwege overschrijden tijdsperiode.")
        }
	    $tasks.GetEnumerator() | % {
		    $task=$_.value
		    $task.pipeline.stop()
		    $task.pipeline.dispose()	
	    }
    #}

    $pool.Close() #-- playtime is over
    #endregion
}
}
End{

    $temp=(Get-Date)-$TS_StartRCtasks
    $TasksFinishedpMin=[Math]::Round($TaskFinished/$temp.totalMinutes,1)
    $log.verbose("--- " + $TasksFinished + ": Uitgevoerd --" + $TasksFailed + " : mislukt -- " + $TasksFinishedpMin + " : gemiddeld uitgevoerd [n/min] -- ")
    $TS_EndScript=get-date #-- mark the time we stop.
    $log.msg("Einde script om $TS_Endscript. Doorlooptijd "+ ($TS_endScript-$TS_startscript))


}