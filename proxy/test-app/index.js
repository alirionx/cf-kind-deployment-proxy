const http = require("http");
const ms = require("ms");

http
  .createServer((req, res) => res.end(`proxy-test ${ms("2 days")}\n`))
  .listen(process.env.PORT || 8080);
