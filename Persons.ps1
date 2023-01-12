$config = ConvertFrom-Json $configuration;

# Make sure the URL ends with a forward slash
if ($config.dayForceUrl -notmatch "/$") {
    $config.dayForceUrl = $config.dayForceUrl + "/"
}

function Get-DayforceAccessToken {
    $authUrl = "https://dfid.dayforcehcm.com/connect/token"

    $body = @{
        grant_type = "password";
        companyId = $config.dayForceClient;
        username = $config.username;
        password = $config.password;
        client_id = "Dayforce.HCMAnywhere.Client"
    }

    $response = Invoke-WebRequest -uri $authUrl -Method post -body $body -ContentType "application/x-www-form-urlencoded"

    $access_token = $($response.content | ConvertFrom-Json).access_token

    $authorization = [ordered]@{
        authorization = "Bearer $access_token"
    }

    $authorization
}

# Get the authorization header
$authorization = Get-DayforceAccessToken

$baseUri = $config.dayForceUrl + "api/" + $config.dayForceClient + "/" + $config.apiVersion

$response = Invoke-WebRequest -uri $($baseUri + "/Employees?employmentStatusXRefCode=AC") -Method Get -Headers $authorization

$employees = ($response.content | ConvertFrom-Json).data

foreach($employee in $employees)
{
    try {
        $employeeUri = $baseUri + "/Employees/" + $employee.XRefCode + "?expand=EmployeeManagers,EmploymentStatuses"

        $employeeResponse = Invoke-WebRequest -Uri $employeeUri -Method Get -Headers $authorization

        $employeeData = ($employeeResponse.Content | ConvertFrom-Json).data

        $person = @{};
        $person["ExternalId"] = $employee.XRefCode;
        $person["DisplayName"] = $employeeData.DisplayName
        $person["Role"] = "Employee"
        $person["Manager"] = $employeeData.EmployeeManagers.Items[0].ManagerXRefCode
    

        foreach($prop in $employeeData.PSObject.properties)
        {
            if(@("RowError","RowState","Table","HasErrors","ItemArray") -contains $prop.Name) { continue; }
            $person[$prop.Name.replace('-','_')] = "$($prop.Value)";
        }
        
        $person["Contracts"] = [System.Collections.ArrayList]@();

            
        #Assignments
        foreach($assign in $employeeData.EmploymentStatuses.Items)
        {		
            $contract = @{};
            $contract["ExternalId"] = $assign.employeeNumber
            $contract["Role"] = "Employee"
            $contract["Status"] = $assign.EmploymentStatus.LongName
            $contract["StartDate"] = $person.HireDate
            $contract["EndDate"] = $person.TerminationDate
            $contract["TitleId"] = "Employee"
            $contract["Title"] = "Employee"
            $contract["Manager"] = $person['manager'];
            $contract["DepartmentExternalId"] = $employeeData.HomeOrganization[0].XRefCode
            $contract["DepartmentName"] = $employeeData.HomeOrganization[0].LongName
            $contract["DepartmentShortName"] = $employeeData.HomeOrganization[0].ShortName

            foreach($prop in $assign.PSObject.properties)
            {
                if(@("RowError","RowState","Table","HasErrors","ItemArray") -contains $prop.Name) { continue; }
                $contract[$prop.Name.replace('-','_')] = "$($prop.Value)";
            }

    
            [void]$person.Contracts.Add($contract);
        }

        Write-Output ($person | ConvertTo-Json -Depth 50);
    } catch {
        continue;
    }
}
#region Execute

Write-Information "Person import completed"
