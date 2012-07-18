#!/usr/bin/env ruby

require 'rubygems'
require 'trollop'

PDFTOPS = "pdftops"
PSTOPS = "pstops"
PSTOPDF = "pstopdf"
BBOX = "gs -sDEVICE=bbox -dNOPAUSE -dBATCH"

DEPS = [ PDFTOPS, PSTOPS, PSTOPDF, "gs" ]

DEPS.each do |d|
    if `which #{d}`.empty? then
        puts "$0 requires #{d}, but could not find it."
        puts "Ensure pstools, ghostscript, and xpdf are installed, "
        puts "and in your PATH."
        exit
    end
end

# command line parsing

$opts = Trollop::options do
  version "printlncs 0.4 (c) 2012 Michael Emmi"
  banner <<-EOS
printlncs saves you paper when you print out LNCS papers.

Usage:
       printlncs [options] <filename.[pdf,ps]>
where [options] are:
EOS

  opt :letter, "Format for letter paper"
  opt :a4, "Format for A4 paper"
  opt :noscale, "Do not allow scaling"
  opt :offset, "Shift the page", :type => :int, :default => 0
end

Trollop::die "No valid input file given." \
    if not ARGV[0] \
    or (not ARGV[0].include? ".ps" and not ARGV[0].include? ".pdf") \
    or not File.exists? ARGV[0]

class Box
    attr_accessor :x1, :x2, :y1, :y2
    
    def initialize( dimens )
        @x1 = dimens[0]
        @x2 = dimens[2]
        @y1 = dimens[1]
        @y2 = dimens[3]
        @txs = 0, 0
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
        return "[#{@x1},#{@y1},#{@x2},#{@y2}]"
    end
end

$letter_page = Box.new [0,0,612,792]
def $letter_page.type
    "letter"
end
$a4_page = Box.new [0,0,595,842]
def $a4_page.type
    "a4"
end

$page = if $opts[:a4] then $a4_page else $letter_page end

$padding = Box.new [0,0,10,40]

def num_pages(psfile)
    return File.open(psfile).grep(/%%Pages/).first.split(":")[1].strip.to_i
end

def bounds(psfile,pages)
    puts "Computing bounding box for page(s) #{pages.join(", ")}..."
    dimens = pages.map { |page| 
        `psselect -p#{page} #{psfile} 2> /dev/null | #{BBOX} - 2>&1`.
        lines.
        select{|l| l.include? "BoundingBox"}.
        first.split(":")[1].strip.split.map{|s| s.to_i}
    }
    puts "boxes: #{ dimens.map{ |ds| Box.new ds }.join(", ") }"
    return dimens.map{ |ds| Box.new ds }
end

def max(i,j)
    if i > j then i else j end
end
def min(i,j)
    if i < j then i else j end
end

def calculate(box)
    
    ## ToDo -- center the pages, in case of weird scaling
    
    vscale = min( 1, ($page.width - $padding.width).to_f / box.height )
    hscale = min( 1, ($page.height - $padding.height).to_f / (box.width*2))    
    scale = if $opts[:noscale] then 1 else min(vscale,hscale) end
            
    hmargin = ($page.width - box.height*scale) / 2
    vmargin = ($page.height - 2 * box.width*scale) / 3
                
    xo1 = xo2 = hmargin - ($opts[:offset] - box.y2)
    yo1 = vmargin - box.x1
    yo2 = yo1 + vmargin + box.width*scale
                
    puts "Scale = #{scale}"
    puts "X-offsets = #{xo1}, #{xo2}"
    puts "Y-offsets = #{yo1}, #{yo2}"
        
    return scale, xo1, xo2, yo1, yo2
end

def convert(f)
    
    if File.extname(f) == ".ps" then
        src = File.basename(f,".ps")
        
        # copy the input PS file to the working directory
        if File.dirname(f) != Dir.pwd then
            FileUtils.cp(f, "#{src}.ps")
        end
        
    elsif File.extname(f) == ".pdf" then
        
        # convert the input PDF file to a PS file in the working directory
        src = File.basename(f,".pdf")
        puts "Converting #{src}.pdf to #{src}.ps"
        `#{PDFTOPS} \"#{f}\" #{src}.ps`
        
    else
        puts "Warning: expected PDF/PS file; skipping #{File.basename(f)}."
        return
    end
        
    num_pages = min( num_pages("#{src}.ps"), 5 )
    pages = (1..num_pages).map{ |x| x }

    box = Box.avg( bounds("#{src}.ps",pages) )        
    puts "box-avg: #{box}"
    
    scale, xoff1, xoff2, yoff1, yoff2 = calculate(box)

    # scale, rotate, and shift the pages
    str = "2:0L@#{scale}(#{xoff1},#{yoff1})+1L@#{scale}(#{xoff2},#{yoff2})"
    puts "Applying Postsrcipt transformations..."

    # generate a 2-up PS file
    `#{PSTOPS} -p#{$page.type} "#{str}" #{src}.ps #{src}.2up.ps`

    if File.extname(f) == ".pdf" then
        
        # convert back to PDF, if the input file was PDF
        puts "Converting #{src}.2up.ps to #{src}.2up.pdf"
        `#{PSTOPDF} #{src}.2up.ps #{src}.2up.pdf &> /dev/null`
        File.delete("#{src}.ps", "#{src}.2up.ps")
    end
    puts "done."
end

convert(ARGV[0])
