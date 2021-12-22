param ($organization, $project, $token, $pipeline)

## Base64-encodes the Personal Access Token (PAT) appropriately
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes((":{0}" -f $token)))

## We list the pipelines to get the id of the pipeline passed in the argument
Write-Host "Getting pipeline id '$pipeline'..."

$pipelinesURL =  "https://vsrm.dev.azure.com/$organization/$project/_apis/release/definitions?`$top=100&searchText=$pipeline&api-version=6.0"

try {
    $response = Invoke-WebRequest -Uri $pipelinesURL -Method Get -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}

    if($response.statusCode -eq 203) {
        Write-Error "Error 203 'Non-Authoritative Information'. The token entered is invalid, verify that it is not expired or that you have the required permissions."
        Exit
    }
}
catch [System.Net.WebException] {
    if ($_.Exception.Response.StatusCode -eq "NotFound") {
        Write-Error "Resource not found verify organization and project name is correct."
        Exit
    }
}

$content = $response.Content | ConvertFrom-Json

$pipelines = $content.value

$idPipeline
foreach($p in $pipelines) {
    if ($p.name -eq $pipeline) {
        $idPipeline = $p.id
    }
}

if($idPipeline -eq $null) {
    Write-Error "Could not find the pipeline with the name '$pipeline'."
    Exit
}

Write-Host "Pipeline id found: $idPipeline."

## We obtain the releases using the pipeline id.
Write-Host "Getting pipeline releases with id $idPipeline..."
$continuationToken = 0

$releasesURL = "https://vsrm.dev.azure.com/$organization/$project/_apis/release/releases?`$top=100&definitionId=$idPipeline&api-version=6.0"

$results = @()

do {
    $response = Invoke-WebRequest -Uri $releasesURL -Method Get -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}

    $continuationToken = $response.headers["x-ms-continuationtoken"]

    $releasesURL = "https://vsrm.dev.azure.com/$organization/$project/_apis/release/releases?`$top=100&continuationToken=$continuationToken&definitionId=$idPipeline&api-version=6.0"

    $content = $response.Content | ConvertFrom-Json

    $releases = $content.value

    $dataReleases = @()

    foreach($release in $releases){
        $dataRelease= Invoke-RestMethod -Uri $release.url -Method Get -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} 
        $dataReleases += $dataRelease
    }


    foreach($release in $dataReleases) {
        foreach($stage in $release.environments) {
        
            ##Approvals control
            $approvals = "";
            foreach($approval in $stage.preDeployApprovals){
            
                if ($approval.approver){
                    $approvals += $approval.approver.uniqueName 
                    if ($approval.approvedBy){
                        $approvals += "(Approved) "
                    }
                    else
                    {
                        $approvals += "(Pending) "
                    }
                }
                else {
                    if ($approvals -ne "(None)") {
                        $approvals += "(None)"
                    }
                }
            }

            if ($approvals -eq "") {
                $approvals += "(None)"
            }

            ##CreatedOn control
            $createdOn = ""
            if ($stage.createdOn) {
                 $createdOn += $stage.createdOn
            }
            else {
                $createdOn += "(None)"
            }

            $properties = [ordered]@{
              Pipeline    = $release.releaseDefinition.name
              Release     = $release.name
              ReleaseId     = $release.id
              Stage = $stage.name
              StageStatus = $stage.status
              StageId = $stage.id
              CreatedOn = $createdOn
              Approvals = $approvals
            }

            $customObject = New-Object -TypeName PSCustomObject -Property $properties

            $results += $customObject
        }
    }
}
while($continuationToken)


## Order the releases
$results = $results | Sort-Object -Property @{Expression = "Pipeline"}, 
                                            @{Expression = "ReleaseId"; Descending = $False},
                                            @{Expression = "StageId"; Descending = $False}

## File creation
Write-Host "Creating file..."

$date = Get-Date -Format G
$dateFormated = $date.Replace("/", "-").Replace(":", ".")
$fileName = "$pipeline Releases $dateFormated.csv"

$results | Select `
            Pipeline,
            ReleaseId,
            Release,
            Stage,
            StageStatus,
            CreatedOn,
            Approvals | export-csv -Path $fileName -NoTypeInformation

Write-Host "File '$fileName' created."