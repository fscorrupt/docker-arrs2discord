Clear-Host

# Enter the path to the config file for Tautulli and Discord
[string]$strPathToConfig = "$PSScriptRoot\config\config.json"

# Script name MUST match what is in config.json under "ScriptSettings"
[string]$strScriptName = 'ArrsQueue'

<############################################################
    Do NOT edit lines below unless you know what you are doing!
############################################################>

# Define the functions to be used
function Get-SanitizedString {
   [CmdletBinding()]
   param(
      [Parameter(Mandatory)]
      [ValidateNotNullOrEmpty()]
      [string]$strInputString
   )
   # Credit to FS.Corrupt for the initial version of this function. https://github.com/FSCorrupt
   [regex]$regAppendedYear = ' \(([0-9]{4})\)' # This will match any titles with the year appended. I ran into issues with 'Yellowstone (2018)'
   [hashtable]$htbReplaceValues = @{
      'ß' = 'ss'
      'à' = 'a'
      'á' = 'a'
      'â' = 'a'
      'ã' = 'a'
      'ä' = 'a'
      'å' = 'a'
      'æ' = 'ae'
      'ç' = 'c'
      'è' = 'e'
      'é' = 'e'
      'ê' = 'e'
      'ë' = 'e'
      'ì' = 'i'
      'í' = 'i'
      'î' = 'i'
      'ï' = 'i'
      'ð' = 'd'
      'ñ' = 'n'
      'ò' = 'o'
      'ó' = 'o'
      'ô' = 'o'
      'õ' = 'o'
      'ö' = 'o'
      'ø' = 'o'
      'ù' = 'u'
      'ú' = 'u'
      'û' = 'u'
      'ü' = 'u'
      'ý' = 'y'
      'þ' = 'p'
      'ÿ' = 'y'
      '“' = '"'
      '”' = '"'
      '·' = '-'
      ':' = ''
      $regAppendedYear = ''
   }
   
   foreach($key in $htbReplaceValues.Keys){
      $strInputString = $strInputString -Replace($key, $htbReplaceValues.$key)
   }
   return $strInputString
}
function Push-ObjectToDiscord {
   [CmdletBinding()]
   param(
      [Parameter(Mandatory)]
      [ValidateNotNullOrEmpty()]
      [string]$strDiscordWebhook,
      
      [Parameter(Mandatory)]
      [ValidateNotNullOrEmpty()]
      [object]$objPayload
   )
   try {
      $null = Invoke-RestMethod -Method Post -Uri $strDiscordWebhook -Body $objPayload -ContentType 'Application/Json'
      Start-Sleep -Seconds 1
   }
   catch {
      Write-Host "Unable to send to Discord. $($_)" -ForegroundColor Red
      Write-Host $objPayload
   }
}

# Parse the config file and assign variables
[object]$objConfig = Get-Content -Path $strPathToConfig -Raw | ConvertFrom-Json
[string]$strDiscordWebhook = $objConfig.ScriptSettings.$strScriptName.Webhook

# Sonarr Urls/Keys
[object]$SonarrURLs = $objConfig.Sonarr.Urls

# Radarr Urls/Keys
[object]$RadarrURLs = $objConfig.Radarr.Urls

# Get Radarr Queue
$objTemplateRadarr = '' | Select-Object -Property Instance, Title, Message, Status
$objResultRadarr = @()

# Get Radarr Queue
foreach ($RadarrURL in $RadarrURLs){
    # Split URL & Key
    $URL = $RadarrURL.split(";")[0]
    $RadarrApiKey = $RadarrURL.split(";")[1]
    [object]$objRadarrQueue = Invoke-RestMethod -Method Get -Uri "$URL/api/v3/queue/details?apikey=$RadarrApiKey"

    foreach ($Item in $objRadarrQueue ){
        if ($item.status -eq "completed"){
            $objTemp = $objTemplateRadarr | Select-Object *
            $objTemp.Instance = $URL
            $objTemp.Title = $Item.statusMessages.title
            $objTemp.Message = $Item.statusMessages.messages
            $objTemp.Status = $Item.status
            $objResultRadarr += $objTemp
        }
    }
}

$objTemplateSonarr = '' | Select-Object -Property Instance, Title, Message, Status
$objResultSonarr = @()

# Get Sonarr Queue
foreach ($SonarrURL in $SonarrURLs){
    # Split URL & Key
    $URL = $SonarrURL.split(";")[0]
    $SonarrApiKey = $SonarrURL.split(";")[1]
    [object]$objSonarrQueue = Invoke-RestMethod -Method Get -Uri "$URL/api/v3/queue/details?apikey=$SonarrApiKey"

    if ($objSonarrQueue){
    foreach ($Item in $objSonarrQueue ){
        if ($Item.status -eq "completed"){
            $objTemp = $objTemplateSonarr | Select-Object *
            $objTemp.Instance = $URL
            $objTemp.Title = $Item.title
            $objTemp.Message = $Item.statusMessages.messages
            $objTemp.Status = $Item.status
            $objResultSonarr += $objTemp
        }
    }
    }
}

if ($objResultSonarr) {
    # Loop through each Sonarr Queue Item
    [System.Collections.ArrayList]$arrStuckedSonarrDownloadsEmbed = @()
    foreach ($obj in $objResultSonarr) {
        [string]$strSanitizedTitle = Get-SanitizedString -strInputString $obj.title
        [string]$strSanitizedMessage = Get-SanitizedString -strInputString $($obj.Message)
        [string]$strSanitizedInstance = $obj.Instance.split("/").split(".")[2]
        [hashtable]$htbSonarrEmbedParameters = @{
            color       = '15548997'
            title       = "Could not import Item"
            author      = @{
                name     = "Open on $strSanitizedInstance"
                url      = "$($obj.Instance)/activity/queue"
                icon_url = 'https://sonarr.tv/img/logo.png'
            }
            description = "$strSanitizedTitle"
            thumbnail   = @{url = "https://sonarr.tv/img/logo.png" }
            fields      = @{
                name   = 'Error Message: '
                value  = $strSanitizedMessage
                inline = $false
            }, @{
                name   = 'Instance'
                value  = $($obj.Instance)
                inline = $false
            }
            footer      = @{
                text = "Sonarr queue watcher powered by - @fscorrupt"
            }
            timestamp   = ((Get-Date).AddHours(5)).ToString("yyyy-MM-ddTHH:mm:ss.Mss")
        }

        # Add line results to final object
        $null = $arrStuckedSonarrDownloadsEmbed.Add($htbSonarrEmbedParameters)
    

        [object]$objPayloadSonarr = @{
            username = "Sonarr Queue"
            content  = "**Sonarr downloads failed to Import:**"
            embeds   = $arrStuckedSonarrDownloadsEmbed
        } | ConvertTo-Json -Depth 4

        # Send to Discord
        Push-ObjectToDiscord -strDiscordWebhook $strDiscordWebhook -objPayload $objPayloadSonarr
    }
}

if ($objResultRadarr) {
    # Loop through each Radarr Queue Item
    [System.Collections.ArrayList]$arrStuckedRadarrDownloadsEmbed = @()
    foreach ($obj in $objResultRadarr) {
        [string]$strSanitizedTitle = Get-SanitizedString -strInputString $obj.title
        [string]$strSanitizedMessage = Get-SanitizedString -strInputString $($obj.Message)
        [string]$strSanitizedInstance = $obj.Instance.split("/").split(".")[2]
        [hashtable]$htbRadarrEmbedParameters = @{
            color       = '15548997'
            title       = "Could not import Item"
            author      = @{
                name     = "Open on $strSanitizedInstance"
                url      = "$($obj.Instance)/activity/queue"
                icon_url = 'https://radarr.video/img/logo.png'
            }
            description = "$strSanitizedTitle"
            thumbnail   = @{url = "https://radarr.video/img/logo.png" }
            fields      = @{
                name   = 'Error Message: '
                value  = $strSanitizedMessage
                inline = $false
            }, @{
                name   = 'Instance'
                value  = $($obj.Instance)
                inline = $false
            }
            footer      = @{
                text = "Radarr queue watcher powered by - @fscorrupt"
            }
            timestamp   = ((Get-Date).AddHours(5)).ToString("yyyy-MM-ddTHH:mm:ss.Mss")
        }

        # Add line results to final object
        $null = $arrStuckedRadarrDownloadsEmbed.Add($htbRadarrEmbedParameters)
    

        [object]$objPayloadRadarr = @{
            username = "Sonarr Queue"
            content  = "**Sonarr downloads failed to Import:**"
            embeds   = $arrStuckedRadarrDownloadsEmbed
        } | ConvertTo-Json -Depth 4

        # Send to Discord
        Push-ObjectToDiscord -strDiscordWebhook $strDiscordWebhook -objPayload $objPayloadRadarr
    }
}