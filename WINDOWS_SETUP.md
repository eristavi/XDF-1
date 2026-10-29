# XDF-1 on Windows 11 (recommended: WSL2 Ubuntu)

This project uses native Linux tools for RTL verification and generic synthesis. On Windows 11, using WSL2 is the simplest path.

1. Install WSL2 Ubuntu using PowerShell (administrator): `wsl --install -d Ubuntu`
2. Open Ubuntu and install: `sudo apt update && sudo apt install -y python3 python3-venv python3-pip make g++ verilator yosys`
3. Copy or extract the XDF-1 project inside your WSL home directory for reliable file performance.
4. Create a venv and install Python dependencies:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -e . pytest
make python-test
make rtl-lint
make rtl-sim
```

5. Generic RTL synthesis additionally needs **sv2v** and **Yosys**. Refer to the official sv2v installation instructions or use a development image that includes the converter. Then run `make synth`.

Do not assume an RTL PASS until Verilator exits with success. The synthesis report requires a separate successful Yosys run; installing Yosys alone is not sufficient to handle the package-based SystemVerilog source with this project's script.