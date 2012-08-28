# much of the code here is lifted from https://github.com/igrigorik/em-websocket/blob/master/lib/em-websocket/connection.rb

require "thin-em-websocket/version"
require "em-websocket"

module Thin
  module EM
    module Websocket
      class AlreadyUpgradedSocketError < StandardError; end
    end
  end
end

# connection SHIM, so we only override minimal amounts of thin 
class Thin::EM::Websocket::Connection
  attr_writer :max_frame_size

  # define WebSocket callbacks
  def onopen(&blk);     @onopen = blk;    end
  def onclose(&blk);    @onclose = blk;   end
  def onerror(&blk);    @onerror = blk;   end
  def onmessage(&blk);  @onmessage = blk; end
  def onping(&blk);     @onping = blk;    end
  def onpong(&blk);     @onpong = blk;    end

  def trigger_on_message(msg)
    @onmessage.call(msg) if @onmessage
  end
  def trigger_on_open
    @onopen.call if @onopen
  end
  def trigger_on_close
    @onclose.call if @onclose
  end
  def trigger_on_ping(data)
    @onping.call(data) if @onping
  end
  def trigger_on_pong(data)
    @onpong.call(data) if @onpong
  end
  def trigger_on_error(reason)
    return false unless @onerror
    @onerror.call(reason)
    true
  end

  def initialize(connection)
    @connection = connection
  end

  def websocket?
    true
  end

  def upgrade_websocket
    raise ::Thin::EM::Websocket::AlreadyUpgradedSocketError.new if @handler
    @handler = EM::WebSocket::HandlerFactory.build(self, @connection.ws_buffer, false, nil) 
    @handler.run
  end

  # Cache encodings since it's moderately expensive to look them up each time
  ENCODING_SUPPORTED = "string".respond_to?(:force_encoding)
  UTF8 = Encoding.find("UTF-8") if ENCODING_SUPPORTED
  BINARY = Encoding.find("BINARY") if ENCODING_SUPPORTED


  def send_data(data)
    @connection.send_data(data)
  end

  def receive_data(data)
    begin 
      @handler.receive_data(data)
    rescue HandshakeError => e
      trigger_on_error(e)
      # Errors during the handshake require the connection to be aborted
      abort
    rescue WSProtocolError => e
      trigger_on_error(e)
      close_websocket_private(e.code)
    rescue => e
        # These are application errors - raise unless onerror defined
      trigger_on_error(e) || raise(e)
      # There is no code defined for application errors, so use 3000
      # (which is reserved for frameworks)
      close_websocket_private(3000)
    end
  end

  # Send a WebSocket text frame.
  #
  # A WebSocketError may be raised if the connection is in an opening or a
  # closing state, or if the passed in data is not valid UTF-8
  #
  def send(data)
    # If we're using Ruby 1.9, be pedantic about encodings
    if ENCODING_SUPPORTED
      # Also accept ascii only data in other encodings for convenience
      unless (data.encoding == UTF8 && data.valid_encoding?) || data.ascii_only?
        raise WebSocketError, "Data sent to WebSocket must be valid UTF-8 but was #{data.encoding} (valid: #{data.valid_encoding?})"
      end
      # This labels the encoding as binary so that it can be combined with
      # the BINARY framing
      data.force_encoding(BINARY)
    else
      # TODO: Check that data is valid UTF-8
    end

    if @handler
      @handler.send_text_frame(data)
    else
      raise WebSocketError, "Cannot send data before onopen callback"
    end

    # Revert data back to the original encoding (which we assume is UTF-8)
    # Doing this to avoid duping the string - there may be a better way
    data.force_encoding(UTF8) if ENCODING_SUPPORTED
    return nil
  end

  # Send a ping to the client. The client must respond with a pong.
  #
  # In the case that the client is running a WebSocket draft < 01, false
  # is returned since ping & pong are not supported
  #
  def ping(body = '')
    if @handler
      @handler.pingable? ? @handler.send_frame(:ping, body) && true : false
    else
      raise WebSocketError, "Cannot ping before onopen callback"
    end
  end

  # Send an unsolicited pong message, as allowed by the protocol. The
  # client is not expected to respond to this message.
  #
  # em-websocket automatically takes care of sending pong replies to
  # incoming ping messages, as the protocol demands.
  #
  def pong(body = '')
    if @handler
      @handler.pingable? ? @handler.send_frame(:pong, body) && true : false
    else
      raise WebSocketError, "Cannot ping before onopen callback"
    end
  end

  # Test whether the connection is pingable (i.e. the WebSocket draft in
  # use is >= 01)
  def pingable?
    if @handler
      @handler.pingable?
    else
      raise WebSocketError, "Cannot test whether pingable before onopen callback"
    end
  end


  def state
    @handler ? @handler.state : :handshake
  end

  # Returns the maximum frame size which this connection is configured to
  # accept. This can be set globally or on a per connection basis, and
  # defaults to a value of 10MB if not set.
  #
  # The behaviour when a too large frame is received varies by protocol,
  # but in the newest protocols the connection will be closed with the
  # correct close code (1009) immediately after receiving the frame header
  #
  def max_frame_size
    @max_frame_size || EventMachine::WebSocket.max_frame_size
  end

  private

  # As definited in draft 06 7.2.2, some failures require that the server
  # abort the websocket connection rather than close cleanly
  def abort
    @connection.close_connection
  end

  def close_websocket_private(code, body = nil)
    if @handler
      @handler.close_websocket(code, body)
    else
      # The handshake hasn't completed - should be safe to terminate
      abort
    end
  end

end

class Thin::Connection
  # based off https://github.com/faye/faye-websocket-ruby/blob/master/lib/faye/adapters/thin.rb
  # and code in em-websocket

  alias :thin_process      :process
  alias :thin_receive_data :receive_data

  attr_reader :ws_buffer


  def process
    if websocket? 
      @socket_connection = Thin::EM::Websocket::Connection.new(self)
      @request.env['em.connection'] = @socket_connection
      @response.persistent!
    end
    thin_process
  end
  
  def receive_data(data)
    if @socket_connection
      @socket_connection.receive_data(data)
    else 
      @ws_buffer ||= ""
      @ws_buffer << data unless @ws_buffer == false
      @ws_buffer = false if @ws_buffer.length > 10000 # some sane cutoff so we dont have too much data in memory
      thin_receive_data(data)
    end
    
  end

  def websocket?
    return @websocket unless @websocket == nil
    env = @request.env
    @websocket =
      env['REQUEST_METHOD'] == 'GET' and
      env['HTTP_CONNECTION'] and
      env['HTTP_CONNECTION'].split(/\s*,\s*/).include?('Upgrade') and
      env['HTTP_UPGRADE'].downcase == 'websocket'
  end


end
