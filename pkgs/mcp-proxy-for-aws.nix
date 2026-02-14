# mcp-proxy-for-aws - AWS MCP Proxy Server
# https://github.com/aws/mcp-proxy-for-aws
# AWS公式のMCPプロキシサーバーです。
# SigV4認証を処理してAWS MCPサーバーに接続します。
{
  lib,
  python3Packages,
  fetchFromGitHub,
}:
python3Packages.buildPythonApplication rec {
  pname = "mcp-proxy-for-aws";
  version = "1.0.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "aws";
    repo = "mcp-proxy-for-aws";
    tag = "v${version}";
    hash = "sha256-fcj/yigqHCslzj2ollquTD+iPPR13ngcEGs0bizz1qc=";
  };

  build-system = [ python3Packages.hatchling ];

  dependencies = with python3Packages; [
    fastmcp
    boto3
    botocore
  ];

  # Tests require AWS credentials
  doCheck = false;

  pythonImportsCheck = [ "mcp_proxy_for_aws" ];

  meta = {
    description = "MCP Proxy for AWS - Official proxy server for AWS MCP by Amazon";
    homepage = "https://github.com/aws/mcp-proxy-for-aws";
    license = lib.licenses.asl20;
    mainProgram = "mcp-proxy-for-aws";
  };
}
