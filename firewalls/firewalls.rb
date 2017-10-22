#!/usr/bin/env ruby
require 'rubygems'
require 'net/ssh'
require 'fileutils'
require 'timeout'
require 'io/console'
require 'pry'

DUMP_FOLDER = "firewalls"

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
                          :auth_methods => ['password'],
                          :encryption => 'blowfish-cbc', #'aes256-cbc',
                          :port => 22 ) do |ssh|
            ssh.exec!('enable')
            ssh.exec!(password)
            ssh.exec!('changeto system')
            show_context_count = ssh.exec!('show context count')
            show_version = ssh.exec!('show ver')
            show_context = ssh.exec!('show context')
            #ssh.exec('exit')

            #  stdout = ""
            #  ssh.exec("show server names") do |channel, stream, data|
            #    stdout << data #if stream == :stdout
            #  end
            #  puts stdout

            # fix line endings
            show_context_count.gsub!("\n", "\r\n")
            show_version.gsub!("\n", "\r\n")
            show_context.gsub!("\n", "\r\n")

            dump_file = File.open(dumpfile, 'w')
            dump_file.puts show_context_count
            dump_file.puts show_version
            dump_file.puts show_context
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
               :chassis => "", 
               :serial_number => "", 
               :avail => "", 
               :licensed => "", 
               :max => "", 
               :used => ""}
    max = 0
    used = 0

    File.open(inputfile).each(sep=eol) do |line|
      
      chassis_index = line.index('Hardware:   ')
      unless chassis_index.nil?
        hardware = line.slice(chassis_index+12,30)
        chassis = hardware.split(',').first
        chassis.strip!
        current[:chassis] = chassis
      end

      used_index = line.index('Total active Security Contexts:')
      unless used_index.nil?
        used = line.slice(used_index+31,30).strip.to_i
        current[:used] = used
      end

      contexts_index = line.index('Security Contexts')
      perpetual_index = line.index('perpetual')
      unless contexts_index.nil? || perpetual_index.nil?
        colon_index = line.index(':')
        unless colon_index.nil?
          max = line.slice(colon_index+1,4).strip.to_i
          current[:licensed] = max
        end
      end

      sn_index = line.index('Serial Number:')
      unless sn_index.nil?
        serial_number = line.slice(sn_index+14, 20).strip
        current[:serial_number] = serial_number
      end 
      
    end

    current[:avail] = max - used
    record = current[:center] + ', ' + current[:ip] + ', ' + current[:chassis] + ', ' + current[:serial_number] + ', ' + current[:avail].to_s + ', ' + current[:licensed].to_s + ', ' + current[:used].to_s
    out_file.puts record
    nil

  end
  

end


#------------------------------------------------------------------
#------------------------------------------------------------------
# puts " "
# puts " "
# puts "syntax:> ruby firewalls.rb password [username] [ipfile] [datacenterfile] [outputfile]"
# puts " "
# password,username,ipfile,datacenterfile,outputfile = ARGV

# password ||= '___'
# username ||= 'Administrator'
# ipfile ||= 'firewall_ips.txt'
# datacenterfile ||= 'datacenters.txt'
# outputfile ||= 'firewalls.csv'

# puts 'using password = ********'
# puts 'using username = ' + username
# puts 'using ipfile = ' + ipfile
# puts 'using datacenterfile = ' + datacenterfile
# puts 'using outputfile = ' + outputfile
# puts " "

# if (password == '___')
#   puts "ERROR: At minimum, you must include a password on the command line"
#   abort
# end

# if (!File.exist?(ipfile))
#   puts 'ipfile "' + ipfile + '" does not exist'
#   abort
# end  

# if (!File.exist?(datacenterfile))
#   puts 'datacenterfile "' + datacenterfile + '" does not exist'
#   abort
# end  

print "username: "
username = STDIN.gets.strip 
print "password: "
password = STDIN.noecho(&:gets).chomp.strip
puts ""
print "ip file: [firewall_ips.txt]"
ipfile = STDIN.gets.strip 
print "datacenter file: [datacenters.txt]"
datacenterfile = STDIN.gets.strip 
print "output file: [firewalls.csv]"
outputfile = STDIN.gets.strip 

ipfile = 'firewall_ips.txt' if ipfile.empty?
datacenterfile = 'datacenters.txt' if datacenterfile.empty?
outputfile = 'firewalls.csv' if outputfile.empty?

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

# read ip list from file into an array
ips = []
File.open(ipfile).each(sep=eol) do |line|
  line.chomp!
  line.strip!
  if not line.empty?
    ips << line unless line.split('.').count != 4
  end
end

# read datacenter map from file into a hash
datacenter_map = []
File.open(datacenterfile).each(sep=eol) do |line|
  line.chomp!
  line.strip!
  if not line.empty?
    datacenter = line.slice(0,3).strip
    ip_pattern = line.slice(5,20).strip
    datacenter_map.push({:name => datacenter, :pattern => ip_pattern}) unless ip_pattern.split('.').count != 4
  end
end

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
out_file.puts "DataCenter, IP, Model, SerialNo, Avail, Licensed, Used"

# ssh into each firewall and capture a dump
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

#Weaver::parse_dump(eol, 'DEN', '111.222.333.444', 'example.dump', out_file)

puts "COMPLETED"

# clean up
out_file.close
puts "Done writing to " + outputfile
