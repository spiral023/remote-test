import net from "node:net";

const portRaw = process.argv[2];
const port = Number(portRaw);

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  console.error("Usage: node .devcontainer/scripts/claude-ipv4-bridge.mjs <port>");
  process.exit(1);
}

const idleMs = 180000;
let lastActivity = Date.now();

function touch() {
  lastActivity = Date.now();
}

const server = net.createServer((client) => {
  touch();

  const upstream = net.connect({
    host: "::1",
    port,
    family: 6,
  });

  client.on("data", touch);
  upstream.on("data", touch);

  client.on("error", () => {});
  upstream.on("error", (err) => {
    console.error(`[claude-bridge] Upstream-Fehler zu [::1]:${port}: ${err.message}`);
    client.destroy();
  });

  client.on("close", () => upstream.end());
  upstream.on("close", () => client.end());

  client.pipe(upstream);
  upstream.pipe(client);
});

server.on("error", (err) => {
  console.error(`[claude-bridge] Konnte 127.0.0.1:${port} nicht öffnen: ${err.message}`);
  process.exit(1);
});

server.listen({ host: "127.0.0.1", port }, () => {
  console.log(`[claude-bridge] Forwarding 127.0.0.1:${port} -> [::1]:${port}`);
  console.log("[claude-bridge] Läuft bis 3 Minuten Leerlauf, dann beendet es sich selbst.");
});

const timer = setInterval(() => {
  if (Date.now() - lastActivity > idleMs) {
    console.log("[claude-bridge] Keine Aktivität mehr, beende Bridge.");
    clearInterval(timer);
    server.close(() => process.exit(0));
  }
}, 1000);

timer.unref();

process.on("SIGINT", () => {
  server.close(() => process.exit(0));
});

process.on("SIGTERM", () => {
  server.close(() => process.exit(0));
});