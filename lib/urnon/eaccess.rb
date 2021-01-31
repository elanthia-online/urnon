require "openssl"
require "socket"
require "fileutils"
require 'urnon/xdg'

module EAccess
  WORKING_FOLDER = File.join Urnon::XDG.path("eaccess")
  FileUtils.mkdir_p(WORKING_FOLDER)
  PEM = File.join(WORKING_FOLDER, "simu.pem")
  PACKET_SIZE = 8192

  def self.pem_exist?
    File.exist? PEM
  end

  def self.download_pem(hostname = "eaccess.play.net", port = 7910)
    # Create an OpenSSL context
    ctx = OpenSSL::SSL::SSLContext.new
    # Get remote TCP socket
    sock = TCPSocket.new(hostname, port)
    # pass that socket to OpenSSL
    ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
    # establish connection, if possible
    ssl.connect
    # write the .pem to disk
    File.write(EAccess::PEM, ssl.peer_cert)
  end

  def self.verify_pem(conn)
    return if conn.peer_cert.to_s == File.read(EAccess::PEM)
    fail Exception, "\nssl peer certificate did not match #{EAccess::PEM}\nwas:\n#{conn.peer_cert}"
  end

  def self.socket(hostname = "eaccess.play.net", port = 7910)
    download_pem unless pem_exist?
    socket = TCPSocket.open(hostname, port)
    cert_store              = OpenSSL::X509::Store.new
    ssl_context             = OpenSSL::SSL::SSLContext.new
    ssl_context.cert_store  = cert_store
    ssl_context.verify_mode = OpenSSL::SSL::VERIFY_PEER
    cert_store.add_file(EAccess::PEM) if pem_exist?
    ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, ssl_context)
    ssl_socket.sync_close = true
    ssl_socket.connect
    return ssl_socket
  end

  def self.auth(password:, account:, character: nil, game_code: "GS3")
    conn = EAccess.socket()
    # it is vitally important to verify self-signed certs
    # because there is no chain-of-trust for them
    EAccess.verify_pem(conn)
    conn.puts "K\n"
    hashkey = EAccess.read(conn)
    #pp "hash=%s" % hashkey
    password = password.split('').map { |c| c.getbyte(0) }
    hashkey = hashkey.split('').map { |c| c.getbyte(0) }
    password.each_index { |i| password[i] = ((password[i]-32)^hashkey[i])+32 }
    password = password.map { |c| c.chr }.join
    conn.puts "A\t#{account}\t#{password}\n"
    response = EAccess.read(conn)
    fail Exception, "Error(%s)" % response.split(/\s+/).last unless login = /KEY\t(?<key>.*)\t/.match(response)
    #pp "A:response=%s" % response
    conn.puts "M\n"
    response = EAccess.read(conn)
    fail Exception, response unless response =~ /^M\t/
    #pp "M:response=%s" % response
    conn.puts "F\t#{game_code}\n"
    response = EAccess.read(conn)
    fail Exception, response unless response =~ /NORMAL|PREMIUM|TRIAL|INTERNAL|FREE/
    #pp "F:response=%s" % response
    conn.puts "G\t#{game_code}\n"
    EAccess.read(conn)
    #pp "G:response=%s" % response
    conn.puts "P\t#{game_code}\n"
    EAccess.read(conn)
    #pp "P:response=%s" % response
    conn.puts "C\n"
    response = EAccess.read(conn)
    characters = response.sub(/^C\t[0-9]+\t[0-9]+\t[0-9]+\t[0-9]+[\t\n]/, '')
      .scan(/[^\t]+\t[^\t^\n]+/)
      .map {|row| row.split("\t")}
    # for doing stuff with the account
    return yield characters if block_given?
    char_code, _ = characters
      .find { |row| row.last.downcase == character.downcase }

    fail Exception, "%s was not present in:\n- %s" % [character, characters.map(&:last).join("\n- ")] if char_code.nil?

    conn.puts "L\t#{char_code}\tSTORM\n"
    response = EAccess.read(conn)
    fail Exception, response unless response =~ /^L\t/
    #pp "L:response=%s" % response
    conn.close unless conn.closed?
    login_info = Hash[response.sub(/^L\tOK\t/, '')
      .split("\t")
      .map {|kv|
        k,v = kv.split("=")
        [k.downcase, v]
      }]
    return login_info
  end

  def self.read(conn)
    conn.sysread(PACKET_SIZE)
  end
end