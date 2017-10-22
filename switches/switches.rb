#!/usr/bin/env ruby
require 'rubygems'
require 'net/ssh'
require 'fileutils'
require 'timeout'
require 'io/console'
#require 'pry'

DUMP_FOLDER = "switches"

#------------------------------------------------------------------
#------------------------------------------------------------------
module OS
  def OS.windows?
    (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM) != nil
  end

  def OS.mac?
   (/darwin/ =~ RUBY_PLATFORM) != nil
  end

  def OS.unix?
    !OS.windows?
  end

  def OS.linux?
    OS.unix? and not OS.mac?
  end
end

#------------------------------------------------------------------
#------------------------------------------------------------------
module Weaver

  #------------------------------------------------------------------
  def self.capture_ssh (hostname, username, password, dumpfile)
    begin
      Timeout.timeout(12) do
        begin
          Net::SSH.start( hostname, # positional parameter (must be first!)
                          username, 
                          :password => password,
                          :timeout => 10,
                          #:auth_methods => ['password'],
                          #:encryption => 'blowfish-cbc', #'aes256-cbc',
                          :port => 22 ) do |ssh|
            show_hostname = ssh.exec!('show run | inc hostname')
            show_interface_status = ssh.exec!('show interface status')
            show_inventory = ssh.exec!('show inventory')
            #show_run = ssh.exec!('show run')

            #  stdout = ""
            #  ssh.exec("show server names") do |channel, stream, data|
            #    stdout << data #if stream == :stdout
            #  end
            #  puts stdout

            # fix line endings
            show_hostname.gsub!("\n", "\r\n")
            show_interface_status.gsub!("\n", "\r\n")
            show_inventory.gsub!("\n", "\r\n")
            #show_run.gsub!("\n", "\r\n")

            dump_file = File.open(dumpfile, 'w')
            dump_file.puts "hostname #{show_hostname}"
            dump_file.puts show_interface_status
            dump_file.puts show_inventory
            #dump_file.puts show_run
            dump_file.close
          end
        rescue Errno::ECONNREFUSED
          puts "Connection refused for #{hostname}"
          return false
        rescue Errno::ENETUNREACH
          puts "Network unreachable for #{hostname}"
          return false
        rescue Net::SSH::ConnectionTimeout
          puts "Connection timeout for #{hostname}"
          return false
        rescue Net::SSH::AuthenticationFailed
          puts "Authentication failed for #{hostname}"
          return false
        rescue Net::SSH::Disconnect
          puts "Disconnected from #{hostname}"
          return false
        end 
      end
      true
    rescue Timeout::Error
      puts "Timed out trying to get a connection to #{hostname}"
      false
    end
  end

  #------------------------------------------------------------------
  def self.ip_to_datacenter (ip, maps)
    maps.each do |map|
      # Note: the map pattern acts like a regex (but isn't one!) 
      # example: 123.45.#.#

      a,b,c,d = ip.split('.')
      ma,mb,mc,md = map[:pattern].split('.')
      if ((a == ma or ma == "#") and (b == mb or mb == "#") and (c == mc or mc == "#") and (d == md or md == "#"))
        return map[:name]
      end
    end
    "???"
  end

  #------------------------------------------------------------------
  def self.parse_dump (eol, center, ip, inputfile, out_file)
    
    current = {:center => center, 
               :ip => ip,
               :node => "", 
               :chassis => "", 
               :avail => "", 
               :max => "", 
               :used => ""}
    eth_max = 0
    used = 0

    File.open(inputfile).each(sep=eol) do |line|
      
      node_index = line.index('hostname')
      unless node_index.nil?
        node = line.slice(node_index+9,20).strip
        current[:node] = node 
      end

      chassis_index = line.index('NAME: "Chassis", DESCR:')
      unless chassis_index.nil?
        chassis = line.slice(chassis_index+24,30)
        chassis.gsub!('"', '')
        chassis.gsub!('Chassis', '')
        chassis.strip!
        current[:chassis] = chassis
      end

      eth_index = line.index('Eth1/')
      unless eth_index.nil?
        index = line.slice(eth_index+5,3).strip.to_i
        eth_max = index if index > eth_max
        current[:max] = eth_max

        if line.include?('connected')
          used += 1
          current[:used] = used
        end
      end 
      
    end

    current[:avail] = eth_max - used
    record = current[:center] + ', ' + 
             current[:ip] + ', ' + 
             current[:node] + ', ' + 
             current[:chassis] + ', ' + 
             current[:avail].to_s + ', ' + 
             current[:max].to_s + ', ' + 
             current[:used].to_s
    out_file.puts record
    nil

  end
  

end


# puts " "
# puts " "
# puts "syntax:> ruby switches.rb [username] [ipfile] [datacenterfile] [outputfile]"
# puts " "
# password,username,ipfile,datacenterfile,outputfile = ARGV

print "username: "
username = STDIN.gets.strip 
print "password: "
password = STDIN.noecho(&:gets).chomp.strip
puts ""
print "ip file: [switch_ips.txt]"
ipfile = STDIN.gets.strip 
print "datacenter file: [datacenters.txt]"
datacenterfile = STDIN.gets.strip 
print "output file: [switches.csv]"
outputfile = STDIN.gets.strip 

ipfile = 'switch_ips.txt' if ipfile.empty?
datacenterfile = 'datacenters.txt' if datacenterfile.empty?
outputfile = 'switches.csv' if outputfile.empty?

if (password.empty? || username.empty?)
  puts "ERROR: At minimum, you must enter a username and password"
  abort
end

puts ""
puts ""
puts 'using username = ' + username
puts 'using password = ********'
puts 'using ip file = ' + ipfile
puts 'using datacenter file = ' + datacenterfile
puts 'using output file = ' + outputfile
puts ""

if (!File.exist?(ipfile))
  puts 'ipfile "' + ipfile + '" does not exist'
  abort
end  

if (!File.exist?(datacenterfile))
  puts 'datacenterfile "' + datacenterfile + '" does not exist'
  abort
end  

eol = "\r" # default to mac
eol = "\r\n" if OS.windows?
eol = "\n" if OS.linux?

eol = "\r\n"

# read ip list from file into an array
# ips = []
# File.open(ipfile).each(sep=eol) do |line|
#   line.chomp!
#   line.strip!
#   if not line.empty?
#     ips << line unless line.split('.').count != 4
#   end
# end

# read datacenter map from file into a hash
# datacenter_map = []
# File.open(datacenterfile).each(sep=eol) do |line|
#   line.chomp!
#   line.strip!
#   puts line
#   abort
#   if not line.empty?
#     datacenter = line.slice(0,3).strip
#     ip_pattern = line.slice(5,20).strip
#     datacenter_map.push({:name => datacenter, :pattern => ip_pattern}) unless ip_pattern.split('.').count != 4
#   end
# end

# read server list from file into an array
ips = []
File.open(ipfile) do |f|
  f.each_line do |line|
    if not line.empty?
      sip = line.strip
      ips.push sip unless sip.split('.').count != 4
    end
  end
end

# read datacenter map from file into a hash
datacenter_map = []
File.open(datacenterfile) do |f|
  f.each_line do |line|
    if not line.empty?
      datacenter = line.slice(0,3).strip
      ip_pattern = line.slice(5,20).strip
      datacenter_map.push({:name => datacenter, :pattern => ip_pattern}) unless ip_pattern.split('.').count != 4
    end
  end
end

puts "Total number of IPs: #{ips.count}"
puts "Total number of Maps: #{datacenter_map.count}"


# clear/create the dump folder
if Dir.exists?(DUMP_FOLDER)
  puts ""
  puts "You are about to purge all previous dump files from the folder: #{DUMP_FOLDER}"
  print "Continue? (Y/n) "
  doit = $stdin.gets
  doit.strip!.downcase!
  if (doit != 'y' and doit != 'yes' and !doit.empty?)
    puts "OK, we can try again later"
    abort
  end  
  puts ""
end

FileUtils.rm_rf(Dir.glob(File.join(DUMP_FOLDER, '*.txt'))) if Dir.exists?(DUMP_FOLDER)
Dir.mkdir(DUMP_FOLDER) unless Dir.exists?(DUMP_FOLDER)

# create/open the CSV file that will contain the golden output
out_file = File.open(File.join(DUMP_FOLDER, outputfile), 'w')
out_file.puts "DataCenter, IP, Model, Avail, Max, Used"

# ssh into each switch and capture a dump
bad_ips = []
puts "Capturing SSH output..." 
ips.each do |hostname|
  puts "  Capturing #{hostname}"
  dumpfile = File.join(DUMP_FOLDER, "#{hostname}.txt")
  success = Weaver::capture_ssh hostname, username, password, dumpfile
  bad_ips << hostname unless success
end
puts "Capturing SSH output...COMPLETED"

# parse data in all dump files and write csv to out_file
print "Parsing dump files..." 
ips.each do |hostname|
  unless bad_ips.include? hostname
    inputfile = File.join(DUMP_FOLDER, "#{hostname}.txt")
    center = Weaver::ip_to_datacenter hostname, datacenter_map
    Weaver::parse_dump(eol, center, hostname, inputfile, out_file)
    #Weaver::parse_dump(eol, center, hostname, 'example.dump', out_file)
  end  
end

puts "COMPLETED"

# clean up
out_file.close
puts "Done writing to " + outputfile
