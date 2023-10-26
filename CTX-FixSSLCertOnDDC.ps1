# Initialize
$binding = $null
$certbindings = @()

# Get GUID for Broker service
Write-Host "Getting the GUID for the Citrix Broker Service..." -ForegroundColor Yellow
$BrokerService = Get-WmiObject -Class Win32_Product | Select-String -Pattern "citrix broker service"
if ($BrokerService -ne $null)
{
  $BrokerService = $BrokerService.ToString()
  $BrokerServiceSplit1 = $BrokerService.split("{")
  $BrokerServiceSplit2 = $BrokerServiceSplit1[-1].split("}")
  $BrokerGUID = "{"+$BrokerServiceSplit2[0]+"}"
  Write-Host "Citrix Broker Service GUID is $BrokerGUID" -ForegroundColor Green
}
Else
{
  Write-Host "This is not a Citrix Delivery Controller, exiting..." -ForegroundColor Red
  exit 1
}

# Getting and selecting the certificate to bind
Write-Host "`nGetting all certificates from LocalMachine..." -ForegroundColor Yellow
$servercerts = Get-ChildItem Cert:\LocalMachine\My
if (($servercerts.Thumbprint).count -eq 0)
{
  Write-Host "No certificates present, exiting..." -ForegroundColor Red
  exit 1
}
else
{
  Write-Host "Got all certificates from LocalMachine" -ForegroundColor Green
}
if (($servercerts.Thumbprint).count -eq 1)
{
  Write-Host "Only 1 certificate is installed, using that one" -ForegroundColor Green
  $SelectedThumbprint = $servercerts.Thumbprint
}
Else
{
  Write-Host "Select the certificate to bind..." -ForegroundColor Yellow
  $SelectedCert = $servercerts | select Subject, FriendlyName, Thumbprint, NotBefore, NotAfter | Out-GridView -Title "Select Cert to bind:"  -OutputMode Single
  if ($SelectedCert -eq $null)
  {
    Write-Host "No certificate selected, exiting" -ForegroundColor Red
    Exit 1
  }
  Else
  {
    Write-Host "Certificate selected" -ForegroundColor Green
    $SelectedThumbprint = $SelectedCert.Thumbprint
  }
}

# Getting all current bindings
netsh http show sslcert | ForEach-Object{
    if( -not ($_.Trim()) -and $binding )
    {
      $binding = $null
    }

    if( $_ -notmatch '^ (.*)\s+: (.*)$' )
    {
      return
    }

    $name = $matches[1].Trim()
    $value = $matches[2].Trim()

    if( $name -eq 'IP:port' )
    {
      $obj=@{}
      if( $value -notmatch '^(.*):(\d+)$' )
      {
        Write-Error ('Invalid IP address/port in netsh output: {0}.' -f $value)
      }
      else
      {
        $obj = [ordered]@{
          IPAddress = $matches[1].trim()
          Port = $matches[2].trim()
          }
        $certbindings += new-object psobject -Property $obj
      }
    }
}

# Deleting all current bindings 
Write-Host "`nRemoving all current bindings..." -ForegroundColor Yellow
foreach ($certbinding in $certbindings)
{
  $Bindingcombo = ""
  $Bindingcombo = $certbinding.ipaddress + ":" + $certbinding.port

  $DelSsl = netsh http delete sslcert ipport=$Bindingcombo
  $output = "Using netsh to delete certificate binding for " + $bindingcombo + "..."+$DelSsl
  Write-Host $output -ForegroundColor Green
}

# add binding 0.0.0.0:443
write-host "`nCreating new binding..." -ForegroundColor Yellow
$newssl = netsh http add sslcert ipport=0.0.0.0:443 certhash=$SelectedThumbprint appid=$BrokerGUID
$output2 = "Using netsh to create new certificate binding "+"..."+$newssl
Write-Host $output2 -ForegroundColor Green

# restart Citrix broker service
Write-host "`nRestarting Citrix Broker Service..." -ForegroundColor Yellow
Restart-Service -Name "CitrixBrokerService"
Write-Host "Citrix Broker Service restarted" -ForegroundColor Green
