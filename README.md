# Titan CLI

Original Titan runtime preserved from the Moto source phone.

Original verified artifact:
  dist/TitanRuntime-Samsung-20260908-201247.tar.gz

Original bundle contents include:
  TitanRuntimeBundle/INSTALL-SAMSUNG.sh
  TitanRuntimeBundle/payload/bin/titand
  TitanRuntimeBundle/payload/bin/titanctl

Install CLI:
  git clone https://github.com/juliushill42/cli.git
  cd cli
  bash ./install-cli.sh

Verify original artifact:
  titan-cli verify

Install Titan runtime:
  titan-cli install

Runtime control:
  titan-cli start
  titan-cli status
  titan-cli stop

The archive under dist/ remains the original verified Moto transfer artifact.

Owner: Julius Cameron Hill / Titan Universal AI LLC
Watermark: :
