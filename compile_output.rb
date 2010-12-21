require 'rubygems'
require 'ruport'

unless ARGV.length == 2
  puts "invoke with a csv file and collectl output"
  exit
end

class Array
  def sum
    inject(0) {|acc, item| acc + item}
  end  
  def avg
    sum.to_f / length
  end
  
  def second
    self[1]
  end
end  

autoperf = Table(ARGV[0])
stats = ''
File.open(ARGV[1]) {|f| stats = f.readlines}

times = autoperf.column('time').map{|t| DateTime.parse(t)}
ranges = times.zip(times[1..-1])

idle_percents = (2..stats.length).step(15).map do |index|
  next unless stats[index]
  time = DateTime.parse stats[index].match(/.*\((.*)\) \#\#\#$/)[1]
  average_idle = stats[index+4..index+7].map{|r| r.split(' ').last}.inject(0.0){|acc, idle| acc + idle.to_i } /4
  [time, average_idle]
end.compact

hsh = idle_percents.group_by do |time, _| 
  range = ranges.find{|r| r.first <= time && (r[1].nil? || r[1] > time) } 
  range && range.first
end

['min','max','avg'].each do |type|
  autoperf.add_column("idle_time_#{type}") {|r| hsh[DateTime.parse r.time].map(&:second).send(type)}
end  
autoperf.remove_column('time')
puts autoperf.to_csv.gsub(/,/,"\t")


