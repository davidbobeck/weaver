#!/usr/bin/env ruby
require 'rubygems'
require 'net/ssh'
require 'fileutils'

DUMP_FOLDER = "server_dumps"

module Weaver
  def self.capture_ssh (hostname, username, password, dumpfile)
    Net::SSH.start( hostname, username, :password => password ) do |ssh|
      enclosure_info = ssh.exec!('show enclosure info')
      server_names = ssh.exec!('show server names')

      #  stdout = ""
      #  ssh.exec("show server names") do |channel, stream, data|
      #    stdout << data #if stream == :stdout
      #  end
      #  puts stdout

      dump_file = File.open(dumpfile, 'w')
      dump_file.puts enclosure_info
      dump_file.puts server_names
      dump_file.close
    end
  end

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

  def self.parse_dump (center, inputfile, out_file)
    
    File.open(inputfile) do |f|
      current = {:center => center, :enclosure => "", :bay => "", :serial => "", :status => ""}

      f.each_line do |line|
        
        en_index = line.index('Enclosure Name:')
        current[:enclosure] = line.slice(en_index+16,25).strip unless en_index.nil?

        if line.index('[Absent]') == 4
          current[:bay] = line.slice(1,2).strip
          current[:serial] = '************'
          current[:status] = '[Absent]'
          record = current[:center] + ', ' + current[:enclosure] + ', ' + current[:bay].rjust(2) + ', ' + current[:serial] + ', ' + current[:status]
          out_file.puts record
        end

        if line.index('Degraded') == 50
          current[:bay] = line.slice(1,2).strip
          current[:serial] = line.slice(34,15).strip
          current[:status] = 'Degraded'
          record = current[:center] + ', ' + current[:enclosure] + ', ' + current[:bay].rjust(2) + ', ' + current[:serial] + ', ' + current[:status]
          out_file.puts record
        end

        if line.index('OK') == 50
          current[:bay] = line.slice(1,2).strip
          current[:serial] = line.slice(34,15).strip
          current[:status] = 'OK'
          record = current[:center] + ', ' + current[:enclosure] + ', ' + current[:bay].rjust(2) + ', ' + current[:serial] + ', ' + current[:status]
          out_file.puts record
        end
      end
    end
    nil
  
  end

end


#system ("cls")
puts " "
puts " "
puts "syntax:> ruby scraper.rb password [username] [serverfile] [datacenterfile] [outputfile]"
puts " "
password,username,serverfile,datacenterfile,outputfile = ARGV

password ||= '___'
username ||= 'Administrator'
serverfile ||= 'servers.txt'
datacenterfile ||= 'datacenters.txt'
outputfile ||= 'output.csv'

puts 'using password = ********'
puts 'using username = ' + username
puts 'using serverfile = ' + serverfile
puts 'using datacenterfile = ' + datacenterfile
puts 'using outputfile = ' + outputfile
puts " "

if (password == '___')
  puts "ERROR: At minimum, you must include a password on the command line"
  abort
end

if (!File.exist?(serverfile))
  puts 'serverfile "' + serverfile + '" does not exist'
  abort
end  

if (!File.exist?(datacenterfile))
  puts 'datacenterfile "' + datacenterfile + '" does not exist'
  abort
end  

# read server list from file into an array
servers = Array.new
File.open(serverfile) do |f|
  f.each_line do |line|
    if not line.empty?
      sip = line.strip
      servers.push sip unless sip.split('.').count != 4
    end
  end
end

# read datacenter map from file into a hash
datacenter_map = Array.new
File.open(datacenterfile) do |f|
  f.each_line do |line|
    if not line.empty?
      datacenter = line.slice(0,3).strip
      ip_pattern = line.slice(5,20).strip
      datacenter_map.push({:name => datacenter, :pattern => ip_pattern}) unless ip_pattern.split('.').count != 4
    end
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
out_file.puts "DataCenter, EnclosureName, Bay#, SerialNumber, Status"

# ssh into each server and capture a dump
puts "Capturing SSH output..." 
servers.each do |hostname|
  puts "  Capturing #{hostname}"
  dumpfile = File.join(DUMP_FOLDER, "#{hostname}.txt")
  Weaver::capture_ssh hostname, username, password, dumpfile
end
puts "Capturing SSH output...COMPLETED"

# parse data in all dump files and write csv to out_file
print "Parsing dump files..." 
servers.each do |hostname|
  inputfile = File.join(DUMP_FOLDER, "#{hostname}.txt")
  center = Weaver::ip_to_datacenter hostname, datacenter_map
  Weaver::parse_dump center, inputfile, out_file
end
puts "COMPLETED"

# clean up
out_file.close
puts "Done writing to " + outputfile
