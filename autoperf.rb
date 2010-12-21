#--
# Copyright (C)2008 Ilya Grigorik
# You can redistribute this under the terms of the Ruby license
#++

require 'rubygems'
require 'optparse'
require 'ruport'

class AutoPerf
  def initialize(opts = {})
    @conf = {}
    OptionParser.new do |opts|
      opts.banner = "Usage: autoperf.rb [-c config]"

      opts.on("-c", "--config [string]", String, "configuration file") do |v|
        @conf = parse_config(v)
      end
      opts.on("-o", "--output FILE", "output csv file") do |v|
        @output_file = v
      end  
    end.parse!

    run()
  end

  def parse_config(config_file)
    raise Errno::EACCES, "#{config_file} is not readable" unless File.readable?(config_file)

    conf = {}
    open(config_file).each { |line|
      line.chomp
      unless (/^\#/.match(line))
        if(/\s*=\s*/.match(line))
          param, value = line.split(/\s*=\s*/, 2)
          var_name = "#{param}".chomp.strip
          value = value.chomp.strip
          new_value = ''
          if (value)
            if value =~ /^['"](.*)['"]$/
              new_value = $1
            else
              new_value = value
            end
          else
            new_value = ''
          end
          conf[var_name] = new_value
        end
      end
    }

    if conf['wlog']
      conf['wlog'] = Dir[conf['wlog']].sort
    end

    return conf
  end

  def benchmark(conf)
    httperf_opt = conf.keys.grep(/httperf/).collect {|k| "--#{k.gsub(/httperf_/, '')} #{conf[k]}"}.join(" ")
    if conf['wlog']
      wlog = conf['wlog'].shift
      conf['wlog'].push wlog
      wlog_opt = "--wlog n,#{wlog}"
    end
    httperf_cmd = "httperf --hog --server #{conf['host']} --uri #{conf['uri']} --port #{conf['port']} #{httperf_opt} #{wlog_opt}"

    res = Hash.new("")
    res['time'] = Time.now
    IO.popen("#{httperf_cmd} 2>&1") do |pipe|
      puts "\n#{httperf_cmd}"

      while((line = pipe.gets))
        res['output'] += line
        case line
        when /^Total: .*replies (\d+)/ then res['replies'] = $1
        when /^Connection rate: (\d+\.\d)/ then res['conn_per_sec'] = $1
        when /^Request rate: (\d+\.\d)/ then res['req_per_sec'] = $1
        when /^Reply time .* response (\d+\.\d)/ then res['reply_time'] = $1
        when /^Net I\/O: (\d+\.\d)/ then res['net_io_kbs'] = $1
        when /^Errors: total (\d+) client-timo (\d+)/ then 
          res['errors'] = $1
          res['timeout_errors'] = $2
        when /^Reply rate .*min (\d+\.\d) avg (\d+\.\d) max (\d+\.\d) stddev (\d+\.\d)/ then
          res['replies_per_sec_min'] = $1
          res['replies_per_sec_avg'] = $2
          res['replies_per_sec_max'] = $3
          res['replies_per_sec_stddev'] = $4
        when /^Reply status: 1xx=\d+ 2xx=\d+ 3xx=\d+ 4xx=\d+ 5xx=(\d+)/ then res['5xx_status'] = $1
        end
      end
    end

    return res
  end

  def run
    results = {}
    report = Table(:column_names => ['time', 'rate', 'conn_per_sec', 'req_per_sec', 'replies_per_sec_min', 'replies_per_sec_avg','replies_per_sec_max','errors', 'timeout_errors', '5xx_status', 'net_io_kbs'])

    (@conf['low_rate'].to_i..@conf['high_rate'].to_i).step(@conf['rate_step'].to_i) do |rate|
      results[rate] = benchmark(@conf.merge({'httperf_rate' => rate}))
      report << results[rate].merge({'rate' => rate})

      puts report.to_s
      puts results[rate]['output'] if results[rate]['errors'].to_i > 0 || results[rate]['5xx_status'].to_i > 0
    end
    report << [Time.now, *([nil]*10)]
    File.open(@output_file, 'w'){|f| f.write(report.to_csv)}
  end
end

trap("INT") {
  puts "Terminating tests."
  Process.exit
}

AutoPerf.new()
