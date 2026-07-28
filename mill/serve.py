#  test/mill/serve.py — TEST-004: a hermetic smart-HTTP wrapper around
#  `git upload-pack`, so a LOCAL vanilla git repo is clonable by `jab get`
#  on a box with no sshd (a bare local path is not a remote, and `be:`/
#  `file:` want a beagle store).  Lifted from test/get/http/run.sh, which
#  has carried the same fixture since GIT-012.
#
#  Prints the bound port on stdout, then serves until killed.
#  usage: python3 serve.py <repo-path> [port]
import http.server, socketserver, subprocess, sys

REPO = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 0


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        out = subprocess.run(["git", "upload-pack", "--advertise-refs", REPO],
                             capture_output=True).stdout
        pre = b"# service=git-upload-pack\n"
        body = ("%04x" % (len(pre) + 4)).encode() + pre + b"0000" + out
        self.send_response(200)
        self.send_header("Content-Type",
                         "application/x-git-upload-pack-advertisement")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        req = self.rfile.read(n)
        out = subprocess.run(["git", "upload-pack", "--stateless-rpc", REPO],
                             input=req, capture_output=True).stdout
        self.send_response(200)
        self.send_header("Content-Type", "application/x-git-upload-pack-result")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)


socketserver.TCPServer.allow_reuse_address = True
httpd = socketserver.TCPServer(("127.0.0.1", PORT), H)
sys.stdout.write("%d\n" % httpd.server_address[1])
sys.stdout.flush()
httpd.serve_forever()
