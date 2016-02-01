# lambda-promotion

Lambda-promotion is a shell script tool that uses the aws cli to automate the process of creating and updating lambda functions.  It allows to deploy and promote your functions straight from the command line.  This tool was designed for jenkins integration, but can be run locally just as easily.  

## What does it do?

The lambda-promotion tool will create and/or update a lambda function and it's associated dependencies based information supplied in json configuration files.  Unique IAM roles and policies are created for each function.  It also manages function versioning using the alias functionality provided by AWS Lambda.

## Setup
The lambda-promotion tool runs independently of the build process, but requires that certain artifacts are produced.

Below is an example of the file structure resulting from a build.

![Build Artifacts](/images/build-artifacts.png?raw=true)

#### Environments

![Environments Directory](/images/environments.png?raw=true)

The environments directory is required within the deploy directory of the build output, and holds the environment specific configuration files.  These files are created from the lambda.json template (templates/lambda.json) and hold most of the function configuration information.  The filename must match the environment that will be supplied when invoking the script, and have the extension .lam.json.

#### Policy

![Policy.json](/images/policy.png?raw=true)

Also within the deploy directory is the policy.lam.json file.  This will be the policy for the role your lambda function will assume. There may only be one policy document, but the policy may have as many statements as necessary.

Proper policy document can be generated using the [AWS Policy Generator](http://awspolicygen.s3.amazonaws.com/policygen.html), with an IAM policy type.

#### Source code

![Source Code Artifacts](/images/source-artifacts.png?raw=true)

At the top-level of the build output there at least one .zip artifact containing the source code is required.  This is the file that will be uploaded to the lambda function.  Separate archives may be used for each environment, but they may also share a single archive.

#### Events

![Events](/images/events.png?raw=true)

The events directory (located under the deploy directory) is the only optional portion of the build output.  It contains the .json documents defining any of your functions event sources.


## Event sources

The lambda-promotion tool supports multiple types of event-sources.
The currently supported event types are s3, dynamodb, sns, and events (Cloudwatch Scheduled Events).  To include an event source, it must be added to the events array in the environment configuration file.  
Event objects are structured as follows
```
{
  "type": "",
  "src": "",
  "parameter": ""
}
```
The type property identifies the event type (either s3, dynamodb, sns, or events).  

The src key identifies the source json file for the event (from the build output directory e.g. deploy/events/event.json).  Each event type (except for sns) requires a .json file defining it's properties.  The templates for these definitions are located under templates/event-templates.  Any keys marked with a value of '*' Will be automatically filled in by the script.  For sns events, leave this value blank.

The parameter key identifies an additional parameter required for some event-types.  For event-types without a parameter, this field is left blank.  

The event types and their parameters are as follows :
s3: bucket name
dynamodb: table name
sns: topic Arn
events: none

## Usage

The lambda-promotion tool requires two arguments, the path to the build directory, and the environment to use (must have a matching .lam.json config file).

lambda-promotion < build-path > < environment >

lambda-promotion /Users/example/Projects/LambdaProject/build dev

## Dependencies
This tool requires that these cli utilities be installed :  
jq >=1.5  
aws-cli >= 1.3.20
