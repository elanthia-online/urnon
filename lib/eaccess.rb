require "openssl"
require "socket"

module EAccess
  PEM = File.join(__dir__, "..", "simu.pem")
  PACKET_SIZE = 8192
  
  def self.download_pem()
    conn = self.socket()
    File.write(EAccess::PEM, conn.peer_cert)
    # pp "wrote peer certificate to %s" % PEM
  end

  def self.verify_pem(conn)
    return if conn.peer_cert.to_s == File.read(EAccess::PEM)
    fail Exception, "\nssl peer certificate did not match #{EAccess::PEM}\nwas:\n#{conn.peer_cert}"
  end

  def self.socket(hostname = "eaccess.play.net", port = 7910)
    socket = TCPSocket.open(hostname, port)
    cert_store              = OpenSSL::X509::Store.new
    ssl_context             = OpenSSL::SSL::SSLContext.new
    ssl_context.cert_store  = cert_store
    #ssl_context.options     = (OpenSSL::SSL::OP_NO_SSLv2 + OpenSSL::SSL::OP_NO_SSLv3)
    ssl_context.verify_mode = OpenSSL::SSL::VERIFY_PEER
    cert_store.add_file(EAccess::PEM)
    ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, ssl_context)
    ssl_socket.sync_close = true
    ssl_socket.connect
    return ssl_socket
  end

  def self.auth(password:, account:, character:, game_code: "GS3")
    conn = EAccess.socket()
    # it is vitally important to verify self-signed certs 
    # because there is no chain-of-trust for them
    EAccess.verify_pem(conn)
    conn.puts "K\n"
    hashkey = EAccess.read(conn)
    # pp "hash=%s" % hashkey
    password = password.split('').map { |c| c.getbyte(0) }
    hashkey = hashkey.split('').map { |c| c.getbyte(0) }
    password.each_index { |i| password[i] = ((password[i]-32)^hashkey[i])+32 }
    password = password.map { |c| c.chr }.join
    conn.puts "A\t#{account}\t#{password}\n"
    response = EAccess.read(conn)
    fail Exception, "Error(%s)" % response.split(/\s+/).last unless login = /KEY\t(?<key>.*)\t/.match(response)
    # pp "response=%s" % response
    conn.puts "M\n"
    response = EAccess.read(conn)
    fail Exception, response unless response =~ /^M\t/
    # pp "response=%s" % response
    conn.puts "F\t#{game_code}\n"
    response = EAccess.read(conn)
    fail Exception, response unless response =~ /NORMAL|PREMIUM|TRIAL|INTERNAL|FREE/
    # pp "response=%s" % response
    conn.puts "G\t#{game_code}\n"
    EAccess.read(conn)
    # pp "response=%s" % response
    conn.puts "P\t#{game_code}\n"
    EAccess.read(conn)
    # pp "response=%s" % response
    conn.puts "C\n"
    response = EAccess.read(conn)
    # pp "response=%s" % response
    char_code = response.sub(/^C\t[0-9]+\t[0-9]+\t[0-9]+\t[0-9]+[\t\n]/, '')
      .scan(/[^\t]+\t[^\t^\n]+/)
      .find { |c| c.split("\t")[1] == character }
      .split("\t")[0]
    conn.puts "L\t#{char_code}\tSTORM\n"
    response = EAccess.read(conn)
    fail Exception, response unless response =~ /^L\t/
    conn.close unless conn.closed?
    response.sub(/^L\tOK\t/, '').split("\t")
    login[:key]
  end

  def self.read(conn)
    conn.sysread(PACKET_SIZE)
  end
end

EAccess.download_pem() if ARGV.include?("--download-pem")