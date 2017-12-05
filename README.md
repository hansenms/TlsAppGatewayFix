Disabling TLS 1.0 in Azure Web App using App Gateway
====================================================

Background
----------

[Azure Web Apps](https://azure.microsoft.com/en-us/services/app-service/web/) are a great way to deploy modern web applications in a Platform as a Service (PaaS) environment. One of the main advantages is that you do not need to manage your own server. There are, however, some situations where you need more control over the environment than a Web App will allow. As an example, it has been recommended by NIST that [TLS 1.0 be disabled](https://www.nist.gov/news-events/news/2014/04/nist-revises-guide-use-transport-layer-security-tls-networks). Currently, it is not possible for users to disble this protocol on Azure Web Apps, which may prevent an application from meeting security guidelines. 

To fix this, it is possible to put an Azure Application Gateway in front of your application as [described here](https://docs.microsoft.com/en-us/azure/application-gateway/application-gateway-end-to-end-ssl-powershell). More specifics on combining Azure Application Gateway and Azure Web Apps can also be [found here](https://docs.microsoft.com/en-us/azure/application-gateway/application-gateway-web-app-powershell).

The scripts in this repository can be used to deploy this fix for all Web App wendpoints associated with a Traffic Manager. If you have a public facing website deployed in multiple regions and DNS loadbalanced with a Traffic Manager, the solution described here could be a good starting point for you. 

This sort of fix has to be done carefully. It is difficult to repair a plane while it is flying. Please be very careful about running the scripts in this repository without reading it carefully to understand all the implications. You should also deploy the fix in a testing environment first before attempting to deploy this to a production application. The scripts are simply provided as inspiration, you will alsmost certainly need to make modifications to fit your environment. 


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

You can deploy the TLS fix with something like:

```commandline
.\DeployAppGatewayTlsFix.ps1 -ResourceGroupName <RESOURCE GROUP> -TrafficManagerProfileName <TM NAME> `
-CertificatePath <PATH TO PFX> -Environment AzureUsGovernment
```

You will be prompted for a password for the SSL cert.

To Do List
----------

 * Investigate implications of Dynamic Public IP on Gateway and IP restrictions on Web App. It is [not possible](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-network-ip-addresses-overview-arm) to assign a static public IP address to an Application Gateway. 
