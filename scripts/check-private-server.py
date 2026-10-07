"""Run the RDPX client against local hbbs/hbbr using an isolated database."""
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time


def wait_for_port(port, process):
    for _ in range(100):
        if process.poll() is not None:
            raise RuntimeError(f"Server exited before port {port} opened")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    raise TimeoutError(f"Server port {port} did not open")


def main():
    client = Path(__file__).resolve().parents[1]
    args = [arg for arg in sys.argv[1:] if arg != "--build"]
    server = Path(args[0]).resolve() if args else client.parent / "rustdesk-server"
    if "--build" in sys.argv:
        with tempfile.TemporaryDirectory(prefix="rdpx-build-") as directory:
            schema = Path(directory) / "schema.sqlite3"
            shutil.copyfile(server / "db_v2.sqlite3", schema)
            env = os.environ.copy()
            env["DATABASE_URL"] = f"sqlite://{schema.as_posix()}"
            subprocess.run(["cargo", "build", "--locked", "--bins"], cwd=server, env=env, check=True)
        subprocess.run(["cargo", "build", "--locked", "-p", "hbb_common", "--features", "webrtc", "--example", "rdpx_check"], cwd=client, check=True)
    suffix = ".exe" if os.name == "nt" else ""
    # hbbr reserves loopback TCP for its management command socket.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as route:
        route.connect(("192.0.2.1", 9))
        local_ip = route.getsockname()[0]
    processes = []
    with tempfile.TemporaryDirectory(prefix="rdpx-check-") as directory:
        root = Path(directory)
        env = os.environ.copy()
        env.update(DB_URL=str(root / "test.sqlite3"), RUSTDESK_VERSION_SERVER="", RUST_LOG="info")
        with (root / "server.log").open("w", encoding="utf-8") as output:
            try:
                hbbs = server / "target/debug" / f"hbbs{suffix}"
                hbbr = server / "target/debug" / f"hbbr{suffix}"
                processes.append(subprocess.Popen([str(hbbs), "-p", "32116", "-k", "-", "--must-login", "N"], cwd=root, env=env, stdout=output, stderr=output))
                wait_for_port(32116, processes[-1])
                processes.append(subprocess.Popen([str(hbbr), "-p", "32117", "-k", "-"], cwd=root, env=env, stdout=output, stderr=output))
                wait_for_port(32117, processes[-1])
                check = client / "target/debug/examples" / f"rdpx_check{suffix}"
                result = subprocess.run([str(check), "127.0.0.1:32116", f"{local_ip}:32117", str(root / "id_ed25519.pub")], cwd=root, env=env, timeout=55)
                if result.returncode:
                    output.flush()
                    print((root / "server.log").read_text(encoding="utf-8", errors="replace")[-5000:])
                return result.returncode
            finally:
                for process in processes:
                    if process.poll() is None:
                        process.terminate()
                for process in processes:
                    process.wait(timeout=10)


if __name__ == "__main__":
    sys.exit(main())
