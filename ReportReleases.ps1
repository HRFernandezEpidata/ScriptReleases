param ($organization, $project, $token, $pipeline)

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
                $approvals += "(None)"
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


## Order the releases
$results = $results | Sort-Object -Property @{Expression = "Pipeline"}, 
                                            @{Expression = "ReleaseId"; Descending = $False},
                                            @{Expression = "StageId"; Descending = $False}

## Filter by pipeline name
$resultsFiltered = $results | ?{ $_.Pipeline -eq "New release pipeline" }

## File creation
$date = Get-Date -Format G
$dateFormated = $date.Replace("/", "-").Replace(":", ".")
$fileName = "$pipeline Releases $dateFormated.csv"

$resultsFiltered | Select `
            Pipeline,
            ReleaseId,
            Release,
            Stage,
            StageStatus,
            CreatedOn,
            Approvals | export-csv -Path $fileName -NoTypeInformation