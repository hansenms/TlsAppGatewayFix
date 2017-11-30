Disabling TLS 1.0 in Azure Web App using App Gateway
====================================================

Background
----------


Test Environment
-----------------

The script `SetUpTlsTestEnvironment.ps1` establishes a multi-region web application deployment with a traffic manager and SSL cert installed on the web apps. To establish the environment, run the script with:

```commandline
.\SetUpTlsTestEnvironment.ps1 -ResourceGroupName <GRP NAME> -Fqdn <DOMAIN NAME> `
-CertificatePath <PATH TO CERT> -Locations usgovvirginia,usgovtexas `
-Environment AzureUsGovernment
```

You will be prompted for a certificate password and you will also be asked to establish a CNAME record for the domain name you will be using for the app. Please make sure that the record is active before proceeding. 