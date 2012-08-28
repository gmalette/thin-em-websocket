require 'thin-em-websocket'

echo = lambda do |env|
  connection = env['em.connection']
  if connection && connection.websocket? 
    puts "upgrading web socket"
    begin
      connection.upgrade_websocket
    rescue => e
      p "#{e}"
      e.backtrace.each do |b|
        p b
      end
    end
    connection.onmessage { |m| 
      puts "GOT #{m}"
      connection.send(m)
      puts "SEND #{m}"
    }
    return Thin::Connection::AsyncResponse
  end

  [200, {"Content-Type" => "text/html"}, [<<-HTML
    <html>
    <body>
      <script>
        socket = new WebSocket("ws://" + document.location.hostname + ":" + (document.location.port || 80) + "/ws");
        socket.onerror = function(m){ alert("error: " + m); };
        socket.onopen = function() { alert("connected"); socket.send("hello world") };
        socket.onmessage = function(msg) { alert(msg.data); }
      </script>
    </body>
    </html>
HTML
  ]]
end
 
run echo
