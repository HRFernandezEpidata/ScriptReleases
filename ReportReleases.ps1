param ($organization, $project, $token)

# Base64-encodes the Personal Access Token (PAT) appropriately
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes((":{0}" -f $token)))

#BaseUrl
$apiURL = "https://vsrm.dev.azure.com/$organization/$project/_apis/release/releases?api-version=6.0"

#Request           

$response = Invoke-RestMethod -Uri $apiURL -Method Get -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} 

$releases = $response.value


$dataReleases = @()

foreach($release in $releases){
    $dataRelease= Invoke-RestMethod -Uri $release.url -Method Get -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} 
    $dataReleases += $dataRelease
}


$results = @()

foreach($release in $dataReleases){

    foreach($stage in $release.environments){
        $properties = [ordered]@{
          Pipeline    = $release.releaseDefinition.name
          Release     = $release.name
          ReleaseId     = $release.id
          Stage = $stage.name
          StageStatus = $stage.status
          StageId = $stage.id
          CreatedOn = $stage.createdOn 
        }

        $customObject = New-Object -TypeName PSCustomObject -Property $properties

        $results += $customObject

    }
           
}

$results = $results | Sort-Object -Property @{Expression = "Pipeline"}, 
                                            @{Expression = "ReleaseId"; Descending = $False},
                                            @{Expression = "StageId"; Descending = $False}

$date = Get-Date -Format G
$dateFormated = $date.Replace("/", "-").Replace(":", ".")
$fileName = "Releases $dateFormated.csv"

$results | Select `
            Pipeline,
            Release,
            Stage,
            StageStatus,
            CreatedOn | export-csv -Path $fileName -NoTypeInformation


##qgiplmj4bufpoxympzdwfjcgtzsvd3l455ck3eok2gkxefpgy52q