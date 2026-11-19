/// Web: browsers cannot open raw TCP sockets, so everything stays on HTTPS.
R runWithDltp<R>(R Function() body) => body();
