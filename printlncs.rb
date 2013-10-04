#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'

def psselect
  abort "cannot find 'psselect' in executable path." if `which psselect`.empty?
  return "psselect"
end

def pdftops
  abort "cannot find 'pdftops' in executable path." if `which pdftops`.empty?
  return "pdftops"
end

def pstops
  abort "cannot find 'pstops' in executable path." if `which pstops`.empty?
  return "pstops"
end

def pstopdf
  abort "cannot find 'pstopdf' in executable path." if `which pstopdf`.empty?
  return "pstopdf"
end

def calcbbox
  abort "cannot find 'gs' in executable path." if `which gs`.empty?
  return "gs -sDEVICE=bbox -dNOPAUSE -dBATCH"
end

class Document
  attr_accessor :paper
  attr_accessor :scaling
  attr_accessor :shift
  attr_accessor :hsep
  attr_accessor :first_page
  
  def initialize(src, loud=false, quiet=false)
    @ext = File.extname(src)
    @src = File.basename(src,@ext)
    @loud = loud
    @quiet = quiet
    @calculated = false

    @paper = :letter
    @scaling = 1
    @shift = 0
    @hsep = 0
    @first_page = 1

    case @ext
    when ".ps"
      FileUtils.cp(src, psfile) if File.dirname(src) != Dir.pwd
    when ".pdf"
      puts "Converting #{src} to #{psfile}" unless @quiet
      `#{pdftops} \"#{src}\" \"#{psfile}\"`
    else
      abort "expected .pdf or .ps file; got #{File.basename(src)}."
    end

    puts "Detected #{page_type}-sized paper." if @loud
  end
  
  def ps_transform(scale,xo1,xo2,yo1,yo2)
    "2:0L@#{scale}(#{xo1},#{yo1})+1L@#{scale}(#{xo2},#{yo2})"
  end
  
  def psfile
    "#{@src}.ps"
  end
  
  def ps2up
    "#{@src}.2up.ps"
  end
  
  def num_pages
    File.open(psfile).grep(/%%Pages/).first.split(":")[1].strip.to_i
  end
  
  def page_type
    case File.open(psfile).grep(/%%DocumentMedia/).first.split(":")[1].split.first
    when "612x792"
      "letter"
    when "430x660"
      "lncs"
    when "595x842"
      "a4"
    else
      return "?"
    end
  end

  def recalculate
    puts "Calculating scaling and offsets." unless @quiet
    
    case @paper
    when :letter
      page = Box.letter
    when :a4
      page = Box.a4
    else
      abort "unexpected paper format: #{@paper}"
    end

    # calculate the bounding box as the average across up to five pages
    # from @first_page.
    first = @first_page
    last = @first_page + [[num_pages - first, 0].max, 5].min
    bounding_box = Box.avg((first..last).to_a.map{ |n| Box.new(
      `#{psselect} -p#{n} #{psfile} 2> /dev/null | #{calcbbox} - 2>&1`.
      lines.
      select{|l| l =~ /BoundingBox/}.
      first.
      split(":")[1].strip.split.map{|s| s.to_i}
    )})

    if @scaling then
      @scale = [ 
        (page.width - Box.padding.width).to_f / bounding_box.height,
        (page.height - Box.padding.height).to_f / (bounding_box.width*2),
        1 ].min
    else
      @scale = 1
    end
         
    hmargin = (page.width - bounding_box.height*@scale) / 2
    vmargin = (page.height - 2 * bounding_box.width*@scale) / 3
                
    @xo1 = @xo2 = hmargin + bounding_box.y2*@scale - @shift
    @yo1 = vmargin - bounding_box.x1*@scale + @hsep
    @yo2 = @yo1 + vmargin + bounding_box.width*@scale - 2*@hsep
    
    if @loud
      puts "bounding box: #{bounding_box} -- average from page #{first} to #{last}"
      puts "scaling: #{@scale}"
      puts "x-offsets: #{@xo1}, #{@xo2}"
      puts "y-offsets: #{@yo1}, #{@yo2}"
    end
    
    calculated = true
  end

  # Create a two-page-in-one postscript file, by scaling, rotating, etc.
  def create2up
    recalculate unless @calculated

    # NOTE: pstops doesn't seem to allow us to set the page size.
    puts "Applying Postscript transformations..." unless @quiet
    puts "WARNING: scaling by #{@scale}" unless @quiet if @scale != 1
    `#{pstops} -p#{@paper} "#{ps_transform(@scale,@xo1,@xo2,@yo1,@yo2)}" #{psfile} #{ps2up} #{@loud ? "" : "&> /dev/null"} `

    # Convert back to PDF, if PDF was input
    if @ext == ".pdf" then
      puts "Converting #{ps2up} back to #{@src}.2up.pdf" unless @quiet
      `#{pstopdf} #{ps2up} #{@src}.2up.pdf #{@loud ? "" : "&> /dev/null"}`
      File.delete(psfile, ps2up)
    end
  end  
  
  def self.cmdline(args)
    loud = quiet = nil
    options = []
    OptionParser.new do |opts|
      opts.banner = "Usage: #{File.basename $0} [options] FILE"
      
      opts.on("-q", "--quiet", "Run quietly.") do |q|
        loud = !quiet = q
      end

      opts.on("-v", "--verbose", "Run verbosely.") do |v|
        quiet = !loud = v
      end
    
      opts.on("--[no-]scale", "Do (not) allow scaling.") do |s|
        options << lambda{|d| d.scaling = s}
      end
    
      opts.on("--paper SIZE", [:letter, :a4], "Set paper SIZE.") do |p|
        options << lambda{|d| d.paper = p}
      end
    
      opts.on("--offset LENGTH", Integer, "Shift the page by LENGTH.") do |o|
        options << lambda{|d| d.shift = o}
      end
    
      opts.on("--hsep LENGTH", Integer, "Add LENGTH to horizontal space.") do |h|
        options << lambda{|d| d.hsep = h}
      end
    
      opts.on("--first-page PAGE", Integer, "Calculate bounding boxes from PAGE.") do |p|
        options << lambda{|d| d.first_page = p}
      end
    end.parse!(args)

    abort "Must specify a single input file." unless args.size == 1
    abort "Input file #{args[0]} does not exist." unless File.exists?(args[0])
    d = Document.new(args[0],loud,quiet)
    options.each{|o| o.call(d)}
    d.create2up
  end
end

class Box
  attr_accessor :x1, :x2, :y1, :y2
  
  def initialize( dimens )
    @x1 = dimens[0]
    @x2 = dimens[2]
    @y1 = dimens[1]
    @y2 = dimens[3]
    @txs = 0, 0
  end
  
  def self.letter
    Box.new [0,0,612,792]
  end
  
  def self.a4
    Box.new [0,0,595,842]
  end
  
  def self.padding
    Box.new [0,0,10,40]
  end
  
  def width
    @x2 - @x1
  end
  
  def height
    @y2 - @y1
  end
  
  def +( b )
    return Box.new [ @x1+b.x1, @y1+b.y1, @x2+b.x2, @y2+b.y2 ]
  end
      
  def map( fn )
    return Box.new [ 
      fn.call(@x1), fn.call(@y1), 
      fn.call(@x2), fn.call(@y2) ]
  end
          
  def self.avg( boxes )
    return boxes.
      reduce{ |sum,b| sum + b }.
      map( lambda{ |x| (x.to_f / boxes.size).to_i } )
  end

  def to_s
    return "(#{@x1},#{@y1}),(#{@x2},#{@y2})"
  end
end


Document.cmdline(ARGV) if __FILE__ == $0
