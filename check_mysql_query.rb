#!/usr/bin/ruby1.9.1

# Name: check_mysql_query.rb
# Author: Daniel Maher (github.com/phrawzty)
# Description: Nagios plugin that performs a MySQL query and parses the result.
#              This is largely lifted from my check_http_json.rb plugin. :P



# Requires
require 'mysql2'
require 'yaml'
require 'optparse'



# Globals
@options = {}



# Subs

# Display verbose output (if being run by a human for example).
def say msg
    if @options[:verbose] == true
        puts '+ %s' % [msg]
    end
end

# Perform the query and return the result
def query(host, user, pass, db, query)
    begin
        client = Mysql2::Client.new(
                :host => host,
                :username => user,
                :password => pass,
                :database => db)
    rescue Mysql2::Error => e
        puts config
        puts "CRIT: #{e.message}"
        exit 3
    end

    result = client.query(query)

    return result.first.values.first
end

# Manage the exit code explicitly.
def do_exit code
    if @options[:verbose] == true
        exit(3)
    else
        exit(code)
    end
end

# Parse the nutty Nagios range syntax.
# http://nagiosplug.sourceforge.net/developer-guidelines.html#THRESHOLDFORMAT
def nutty_parse(thresh, want, got)
    retval = 'FAIL'

    # if there is a non-numeric character we have to deal with that
    # got < want
    if want =~ /^(\d+):$/ then
        if got.to_i < $1.to_i then
            retval = 'KO'
        else
            retval = 'OK'
        end
    end

    # got > want
    if want =~ /^~:(\d+)$/ then
        if got.to_i > $1.to_i then
            retval = 'KO'
        else
            retval = 'OK'
        end
    end

    # outside specific range
    if want =~ /^(\d+):(\d+)$/ then
        if got.to_i < $1.to_i or got.to_i > $2.to_i then
            retval = 'KO'
        else
            retval = 'OK'
        end
    end

    # inside specific range
    if want =~ /^@(\d+):(\d+)$/ then
        if got.to_i >= $1.to_i and got.to_i <= $2.to_i then
            retval = 'KO'
        else
            retval = 'OK'
        end
    end

    # otherwise general range
    if not want =~ /\D/ then
        if got.to_i < 0 or got.to_i > want.to_i then
            retval = 'KO'
        else
            retval = 'OK'
        end
    end

    if retval == 'OK' then
        say('%s threshold not exceeded.' % [thresh])
    elsif retval == 'KO' then
        say('%s threshold exceeded.' % [thresh])
    else
        say('"%s" is a strange and confusing %s value.' % [want, thresh])
    end

    return retval
end



# Runtime.

# Parse cli args.
optparse = OptionParser.new do |opts|
    opts.banner = "Usage #{$0} -c <config_file> [-v]"

    opts.on('-h', '--help', 'Help!') do
        puts opts
        exit 3
    end

    @options[:verbose] = false
    opts.on('-v', '--verbose', 'Human output') do
        @options[:verbose] = true
    end

    @options[:query] = nil
    opts.on('-q', '--query \'QUERY\'', 'The query to execute') do |x|
        @options[:query] = x
    end

    @options[:result_string] = nil
    opts.on('-s', '--result STRING', 'Expected (string) result. No need for -w or -c.') do |x|
        @options[:result_string] = x
    end

    @options[:result_regex] = nil
    opts.on('-r', '--regex REGEX', 'Expected (string) result expressed as regular expression. No need for -w or -c.') do |x|
        @options[:result_regex] = x
    end

    @options[:warn] = nil
    opts.on('-w', '--warn VALUE', 'Warning threshold') do |x|
        @options[:warn] = x.to_s
    end

    @options[:crit] = nil
    opts.on('-c', '--crit VALUE', 'Critical threshold') do |x|
        @options[:crit] = x.to_s
    end

    @options[:config_file] = nil
    opts.on('-f', '--file CONFIG_FILE', 'Config file (replaces the switches below).') do |x|
        @options[:config_file] = x
    end

    @options[:mysql_host] = nil
    opts.on('--host', 'MySQL host') do |x|
        @options[:mysql_host] = x
    end

    @options[:mysql_database] = nil
    opts.on('--database', 'MySQL database') do |x|
        @options[:mysql_database] = x
    end

    @options[:mysql_user] = nil
    opts.on('--user', 'MySQL user') do |x|
        @options[:mysql_user] = x
    end

    @options[:mysql_pass] = nil
    opts.on('--pass', 'MySQL pass') do |x|
        @options[:mysql_pass] = x
    end
end

# Choose your arguments wisely.
optparse.parse!

# Load the config file (if appropriate)
config = nil
if @options[:config_file] then
    config = YAML.load_file(@options[:config_file])

    config.each do |x,y|
        @options[x] = y
    end
end

# In life, some arguments cannot be avoided.
err = []
required = [ :mysql_host, :mysql_database, :mysql_user, :mysql_pass, :query ]
required.each do |x|
    if not @options[x] then
        err.push(" #{x}")
    end
end

if err.count > 0 then
    msg = ''
    err.each do |x|
        msg << x
    end
    puts "UNKNOWN: Need to specify:#{msg}."
    do_exit(3)
end

result = nil
result = query(@options[:mysql_host], @options[:mysql_user], @options[:mysql_pass], @options[:mysql_database], @options[:query])

say("Result: \"#{result}\"")

exit_code = 0
warn = nil
crit = nil

# If the element is a string...
if @options[:result_string] then
    if result.to_s == @options[:result_string].to_s then
        exit_code = 0
    else
        exit_code = 2
    end
end

# If we're looking for a regex...
if @options[:result_regex] then
    if result.to_s =~ /#{@options[:result_regex]}/ then
        exit_code = 0
    else
        exit_code = 2
    end
end

# If we're looking for a numeric result...
if @options[:warn] or @options[:crit] then
    if not Float(result) then
        result = 'Result contains non-numeric characters.'
        exit_code = 3
    end
end

if @options[:warn] and not exit_code == 3 then
    nuts = nutty_parse('Warning', @options[:warn], result)
    case nuts
    when 'FAIL'
        result = 'Warn threshold syntax failure.'
        exit_code = 3
    when 'KO' then
        exit_code = 1
    end
end

if @options[:crit] and not exit_code == 3 then
    nuts = nutty_parse('Critical', @options[:crit], result)
    case nuts
    when 'FAIL'
        result = 'Critical threshold syntax failure.'
        exit_code = 3
    when 'KO' then
        exit_code = 2
    end
end

# Assemble the message.
case exit_code
when 0
    msg = 'OK: '
when 1
    msg = 'WARN: '
when 2
    msg = 'CRIT: '
else
    msg = 'UNKNOWN: '
end

msg << "#{result}"

# Finally output the message and exit.
puts msg
do_exit(exit_code)

puts 'UNKNOWN: This should never happen.'
exit(3)
