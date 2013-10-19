#!/usr/bin/env ruby

# Author: Michael Emmi <michael.emmi@gmail.com>
# Copyright 2013 Michael Emmi

require 'optparse'

$loud = false
$quiet = false

$paper = :letter
$scaling = true
$bottom = 0
$between = 0
$box_range = (1..5)
$padding = 10

def define_command( cmd, extras = {} )
  define_method( extras[:name] || cmd.split.first ) do 
    exe = cmd.split.first
    if `which #{exe}`.empty?
      msg = "I cannot find #{exe} in your executable path."
      msg << "\nNOTE: #{exe} is packaged with #{extras[:package]}." if extras[:package]
      abort msg
    end
    return cmd
  end
end

define_command 'pdftops', :package => 'poppler'
define_command 'pstopdf' # packaged with what?
define_command 'pstops', :package => '(La)TeX'
define_command 'psselect', :package => '(La)TeX'
define_command 'gs -sDEVICE=bbox -dNOPAUSE -dBATCH', :name => :get_box, :package => 'ghostscript'

class Range
  def self.from_s(str)
    case str
    when /(\d+,\s*)+\d+/
      str.split(/,/).map{|i| i.to_i}
    when /\(?\d+(\.\.|,)\d+\)?/
      str.gsub(/[()]/,"").split(/\.\.|,/).inject{|i,j| i.to_i..j.to_i}
    when /^\d$/
      [str.to_i]
    else
      abort "I don't know how to treat the \"range\" #{str} you gave me."
    end
  end
end

class SymbolicFile < String
  def initialize(name,keep=false)
    super(name)
    at_exit { File.delete(name) } unless keep
  end  
  
  def self.from(name)
    new(name,true)
  end

  def as(ext, keep=false)
    my_ext = File.extname(self)
    target = File.basename(self,my_ext) + ext
    
    case 
    when my_ext == ext then self

    when my_ext == '.pdf' && ext == '.ps'
      puts "Generating #{target} from #{self}." unless $quiet
      `#{pdftops} \"#{self}\" \"#{target}\"`
      self.class.new(target,keep)

    when my_ext == '.ps' && ext == '.pdf' then
      puts "Generating #{target} from #{self}." unless $quiet
      `#{pstopdf} \"#{self}\" \"#{target}\"`
      self.class.new(target,keep)

    else
      abort "I don't know how to convert #{my_ext} to #{ext}!"
    end
  end
  
  def transform(keep=false)
    abort "I need a postscript file!" unless (ext = File.extname(self))  == '.ps'
    target = File.basename(self,ext) + '.2up.ps'
    puts "Generating #{target} from #{self}." unless $quiet
    `#{pstops} -p#{$paper} "#{yield self}" #{self} #{target} #{$loud ? "" : "&> /dev/null"}`
    self.class.new(target,keep)
  end
end

def page
  case $paper
  when :letter  then [0,0,612,792]
  when :a4      then [0,0,595,842]
  else               abort "I don't know about #{$paper} format."
  end
end

class Array
  def is_point; size == 2 end  
  def x; self[0] end
  def y; self[1] end

  def is_box; size == 4 end
  def x1; self[0] end
  def y1; self[1] end
  def x2; self[2] end
  def y2; self[3] end
  def width; x2 - x1 end
  def height; y2 - y1 end

  alias a_to_s to_s
  def to_s
    return "(#{x},#{y})" if is_point
    return "(#{x1},#{y1}):(#{x2},#{y2})" if is_box
    a_to_s
  end
end

# Generate a postscript transformation string
def magic(psfile)
  
  # calculate the average bounding box over $box_range
  # coordinates are given by [x1,y1,x2,y2]
  bounding_box = $box_range.inject([0,0,0,0]) do |sums,page|
    `#{psselect} -p#{page} #{psfile} 2> /dev/null | #{get_box} - 2>&1`.
    lines.select{|l| l =~ /BoundingBox/}.first.split(':')[1].strip.split.
    each_with_index.map{|n,i| n.to_i + sums[i]}
  end.map{|n| n / $box_range.size}
  
  if $scaling then
    scale = [ 1,
      (page.width - 2 * $padding).to_f / bounding_box.height,
      (page.height - 3 * $padding).to_f / (bounding_box.width*2) ].min
  else scale = 1
  end
  
  horizontal_margin = (page.width - bounding_box.height * scale) / 2
  vertical_margin = (page.height - 2 * bounding_box.width * scale) / 3
  
  left_page_shift = [
    horizontal_margin + bounding_box.y2 * scale - $bottom,
    vertical_margin - bounding_box.x1 * scale - $between
  ]
  
  right_page_shift = [
    horizontal_margin + bounding_box.y2 * scale - $bottom,
    left_page_shift.y + vertical_margin + bounding_box.width * scale + 2 * $between
  ]
  
  if $loud then
    puts "bounding box: #{bounding_box} -- average over pages #{$box_range}"
    puts "scaling: #{scale}"
    puts "left-page-shift: #{left_page_shift}"
    puts "right-page-shift: #{right_page_shift}"
  end

  puts "WARNING: scaling by #{scale}." unless scale == 1 || $quiet
  "2:0L@#{scale}#{left_page_shift}+1L@#{scale}#{right_page_shift}"
end

def cmdline(args)
  OptionParser.new do |opts|
    opts.banner = "Usage: #{File.basename $0} [options] FILE"

    opts.on("-q", "--quiet", "Run quietly.") do |q|
      $loud = !$quiet = q
    end

    opts.on("-v", "--verbose", "Run verbosely.") do |v|
      $quiet = !$loud = v
    end
  
    opts.on("--[no-]scale", "Do (not) allow scaling.") do |s|
      $scaling = s
    end
  
    opts.on("--paper SIZE", [:letter, :a4], "Set paper SIZE.") do |p|
      $paper = p
    end
    
    opts.on("--padding SPACE", Integer, "Add SPACE to bounding boxes.") do |s|
      $padding = s
    end
  
    opts.on("--bottom SPACE", Integer, "Add SPACE to the bottom.") do |s|
      $bottom = s
    end
  
    opts.on("--between SPACE", Integer, "Add SPACE between pages.") do |s|
      $between = s
    end
  
    opts.on("--box-range PAGES", "Calculate bounding boxes on PAGES.") do |r|
      $box_range = Range.from_s(r)
    end
  end.parse!(args)

  abort "Must specify a single input file." unless args.size == 1
  abort "Input file #{args[0]} does not exist." unless File.exists?(args[0])
  
  SymbolicFile.from(args[0]).as('.ps').transform{|x| magic(x)}.as('.pdf',true)
end

cmdline(ARGV) if __FILE__ == $0