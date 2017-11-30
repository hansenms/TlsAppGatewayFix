Disabling TLS 1.0 in Azure Web App using App Gateway
====================================================

Background
----------


Test Environment
-----------------

The script [`SetUpTlsTestEnvironment.ps1`](SetUpTlsEnvironment.ps1) establishes a multi-region web application deployment with a traffic manager and SSL cert installed on the web apps. To establish the environment, run the script with:

```commandline
.\SetUpTlsTestEnvironment.ps1 -ResourceGroupName <GRP NAME> -Fqdn <DOMAIN NAME> `
-CertificatePath <PATH TO CERT> -Locations usgovvirginia,usgovtexas `
-Environment AzureUsGovernment
```

You will be prompted for a certificate password and you will also be asked to establish a CNAME record for the domain name you will be using for the app. Please make sure that the record is active before proceeding. 


Deploying Application Gateway Fix
----------------------------------

The goal is to selective disable TLS protocols and ciphers to meet specific security profiles. The script [`DeployAppGatewayTlsFix.ps1`](DeployAppGatewayTlsFix.ps1) will achieve this by deploying an Application Gateway in front of each web application and setting appropriate configurations on the gateway. 

This script will loop through all registered endpoints of a Traffic Manager. For the end points associated with an
Azure Web App, it will install an Application Gateway in front of the Web App and point the Traffic Manager to the 
Gateway instead. The Gateway will only have TLS 1.1 and above enabled and traffic to the web app will be restricted
such that only traffic from the gateway is allowed. 

