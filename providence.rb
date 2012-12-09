#!/usr/bin/env ruby
require "socket"
require "fiber"
require "stringio"


module Providence
  class Action
    attr_reader :lines

    def initialize
      @queue=StringIO.new
      @lines=[]
      @is_finish=false
    end

    def push(buf)
      buf.each_char do |c|
        case c
        when "\n"
          if @lines.last=="" then
            @is_finish=true
          end
          line=@queue.string
          @queue.string=""
          @lines << line
        when "\r"
          # skip
        else
          @queue << c
        end
      end
    end

    def finish?
      @is_finish=true
    end
  end


  class Server
    def initialize(logger)
      @logger=logger
    end

    def start(port)
      @logger.info "listen port: #{port}"
      @port=port

      listen = TCPServer.open(@port)
      sockets=[listen]
      action_map={}

      while true

        readables, writables, errors = IO::select(sockets)

        readables.each do |socket|
          if socket==listen then
            accepted=socket.accept_nonblock
            sockets << accepted
            @logger.debug "#{accepted}: accepted"
            action_map[accepted]=Fiber.new do |socket|
              action=Action.new

              while true
                begin
                  # async read
                  buf=socket.recv_nonblock(1024)
                  action.push buf
                  if action.finish? 
                    p action.lines
                    break
                  end
                rescue Errno::EAGAIN
                  Fiber.yield
                end
              end
              @logger.debug "#{socket}: finished"
            end
          else
            action=action_map[socket]
            action.resume socket
            unless action.alive? then
              sockets.delete socket
              action_map.delete socket

              socket.write(
                "HTTP/1.0 200 OK\r\n"+
                "\r\n"+
                "HELLO !!"
              )

              socket.close
            end
          end
        end
      end
    end
  end
end


if __FILE__==$0 then
  require 'logger'
  logger=Logger.new STDOUT
  logger.level=Logger::DEBUG
  service=Providence::Server.new(logger)
  service.start (ARGV.size>0 and ARGV[0] or 5000)
end

