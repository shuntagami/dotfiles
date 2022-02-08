#!/usr/bin/env ruby

########################################
# HELP
########################################
HELP=<<EOS
display os version

$ os
Ubuntu 17.04 zesty
EOS

if ARGV[0] == "-h"
  puts HELP
  exit 0
end


########################################
# Main
########################################
if `uname` =~ /Linux/ then
  lsb_release = File.open("/etc/lsb-release")
                    .read
                    .split("\n")
                    .reject{|e| e.start_with?("#") }
                    .map{|e| e.split("=")}
                    .flatten
  release = Hash[*lsb_release]

  productName = release['DISTRIB_ID']
  version     = release['DISTRIB_RELEASE']
  osName      = release['DISTRIB_CODENAME']
  puts "#{productName} #{version} #{osName}"
  exit(0)
end

if `uname` =~ /Darwin/ then
  MacVersion = {
    "12.1"  => "Monterey",
    "12.0"  => "Monterey",
    "11.4"  => "Big Sur",
    "11.3"  => "Big Sur",
    "11.2"  => "Big Sur",
    "11.1"  => "Big Sur",
    "11.0"  => "Big Sur",
    "10.15" => "Catalina",
    "10.14" => "Mojave",
    "10.13" => "High Sierra",
    "10.12" => "Sierra",
    "10.11" => "El Capitan",
    "10.10" => "Yosemite",
  }
  MacVersion.default = "Unknown"

  # https://support.apple.com/en-us/HT201260
  productName = `sw_vers -productName`.sub("\n", "")
  version     = `sw_vers -productVersion`.sub("\n", "")
  osName      = case version.split(".")[0..1].join(".")
                when ->v{ v.start_with?("12.") } then "Monterey"
                when ->v{ v.start_with?("11.") } then "Big Sur"
                when "10.15" then "Catalina"
                when "10.14" then "Mojave"
                when "10.13" then "High Sierra"
                when "10.12" then "Sierra"
                when "10.11" then "El Capitan"
                when "10.10" then "Yosemite"
                else "Unknown"
                end

  puts "#{productName} #{version} #{osName}"
  exit(0)
end
