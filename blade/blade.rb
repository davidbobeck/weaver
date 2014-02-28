system ("cls")
puts "syntax:  >ruby blade.rb [inputfile] [outputfile]"
puts " "
inputfile = ARGV[0] || 'input.txt'
outputfile = ARGV[1] || 'output.csv'
puts 'using inputfile = ' + inputfile
puts 'using outputfile = ' + outputfile
puts " "

if (!File.exist?(inputfile))
  puts 'inputfile "' + inputfile + '" does not exist'
  abort
end  

out_file = File.open(outputfile, 'w')
out_file.puts "MACAddy,NicName"


File.open(inputfile) do |f|
  current = {:bay => "", :port => "", :mac => ""}

  f.each_line do |line|
    #puts line.index('Bay')
    if line.index('Bay') == 33
      current[:bay] = line.slice(37,2).strip
      current[:port] = line.slice(51,2).strip
      current[:mac] = line.slice(57,100).strip

      record = current[:mac] + ',' + 'INT' + current[:bay] + 'P' + current[:port]
      out_file.puts record
    end
  end
end
out_file.close

puts "done writing " + outputfile
