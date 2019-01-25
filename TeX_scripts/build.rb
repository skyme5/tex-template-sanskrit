#!/usr/bin/ruby
# @Author: msumsc
# @Date:   2018-08-27 15:06:35
# @Last Modified by:   Sky
# @Last Modified time: 2019-01-18 00:29:48
require 'logger'
require 'colorize'
require 'fileutils'

# Dir.chdir(ARGV[0])

puts "Running TexTools".colorize(:yellow)

$logger = Logger.new(STDOUT)

class Index
  def initialize(dir = false)
    @basePath = dir == false ? File.expand_path(".") : dir
    @file = File.join(@basePath, "TeX_index", "index.txt")
    raise "INDEX_FILE_NOT_FOUND_ERROR" if !File.exist?(@file)
    @index = []
    generateEntries
  end

  def formatIndexEntry(line)
    entry = line.split("\t")
    case entry.length
    when 3
      group = entry[0] + "!"
      find = entry[1]
      replace = entry[2]
    when 2
      group = entry[0] + "!"
      find = entry[1]
      replace = entry[1]
    when 1
      group = ""
      find = entry[0]
      replace = entry[0]
    when 0
      raise "EMPTY_INDEX"
    end
    return {
      "find" => find,
      "replace" => "#{find}\\index\{#{group}#{replace}\}"
    }
  end

  def generateEntries
    @index = File.open(@file).read.split("\n").compact.uniq
    @index.map!{
      |entry|
      formatIndexEntry(entry)
    }
  end

  def index
    @index
  end

  def process(body)
    for entry in @index
      body.gsub!(entry["find"], entry["replace"])
    end
  end
end

class Acronym
  def initialize
    @basePath = File.join(File.expand_path("."), "TeX_gls")
    @filePath = File.join(@basePath, "acronym.txt")
    @enable = File.exist?(@filePath)
    $logger.warn "No acronym.txt file found" if !@enable
    @list = getAcrList
  end

  def getAcrList
    return [] if !@enable
    return File.open(@filePath).read.split("\n").compact.map!{
      |m|
      data = m.split("\t")
      a = data.first
      b = data.last
      #   {
      #     "entry" => ["\\acrodef{#{a}}[#{a}]{#{b}}",
      #                 "\\newglossaryentry\{default:#{a}\}\{",
      #                 "\ttype=default,",
      #                 "\tname={\\ac\{#{a}\}},",
      #                 "\tdescription={#{b}},",
      #                 "\tsort={#{a}}",
      #                 "}\n"].join("\n"),
      #     "find" => data.first,
      #     "replace" => "\\gls\{default:#{data.first}\}"
      #   }
      # }
      {
        "entry" => ["\\newacronym[longplural={#{b}}]{#{a}}{#{a}}{#{b}}"].join("\n"),
        "find" => a,
        "replace" => "\\gls\{#{a}\}"
      }
    }
  end

  def save
    outPath = File.join(@basePath, "acronym.tex")
    out = File.open(outPath, "w")
    @list.each{
      |item|
      out.puts item["entry"]
    }
    out.close
  end

  def process(body)
    return body if !@enable
    @list.each{
      |item|
      body.gsub!(item["find"], item["replace"])
    }
  end
end

class FindDates
  def initialize(dir = false)
    @basePath = dir == false ? File.expand_path(".") : dir
    @dir = File.join(@basePath, dir == false ? "TeX_files" : dir)
    raise "CHAPTER_DIR_NOT_FOUND" if !Dir.exist?(@dir)
    @files = getChapterFiles
    @dates = findDatesInChapters
  end

  def save
    outPath = File.join(@basePath, "TeX_gls")
    Dir.mkdir(outPath) if !Dir.exist?(outPath)
    path = File.join(outPath, "date.txt")
    if File.exist?(path)
      print "#{path} already exists, overwrite it ? (yes or no): "
      anwer = $stdin.gets.chomp
      if anwer == "yes"
        createFile(path)
      end
    else
      createFile(path)
    end
  end

  def createFile(path)
    out = File.open(path, "w+")
    out.puts @dates.sort
    out.close
    puts "#{@dates.length} Dates saved to #{path}"
  end

  def getChapterFiles
    files = Dir.entries(@dir)
    files.select!{
      |file|
      file.include? ".tex"
    }
    files.map!{
      |file|
      File.join(@dir, file)
    }
    files.compact
  end

  def findDatesInChapters
    puts "No Chapter files found at #{@dir}" if @files.length == 0
    dates = []
    for file in @files
      body = File.open(file).read
      body.scan(/(\d{4}-\d{2}-\d{2})/).each{
        |m|
        dates << m[0]
      }
    end
    puts "#{@files.length} Chapter files processed" if @files.length > 0
    dates.uniq.sort
  end
end

class EndNotes
  def initialize
    @name = "Finds and puts Endnotes from .ref files"
  end

  def process(_file, body)
    file = _file.gsub(File.extname(_file), ".ref")
    if !File.exist?(file)
      return body
    else
      count = -1
      refList = File.open(file).read.split("\n").compact
      data = body.split("\\endnote")
      data.map! {
        |note|
        count = count + 1
        if count < data.length - 1
          note + "\\endnote\{#{refList[count]}\}"
        else
          note
        end
      }
      $logger.warn "Wrong number of ref(#{count},#{refList.length}) encountered in #{_file}".colorize(:red) if count != refList.length
      return data.join("")
    end
  end
end

class GlossaryItems
  def initialize(file)
    @file = file
    @type = getGLSType
    @glsID = @type + ":"
    raise "FILE_NOT_FOUND" if !File.exist?(@file)
    @entries = getGLSEntries
    @glsData = getGLSFileData
  end

  def save
    path = File.join(File.split(@file).first, @type + ".tex")
    createFile(path)
  end

  def createFile(path)
    out = File.open(path, "w+")
    out.puts glsData
    out.close
    puts "Glossary #{@type}.tex saved to #{path}"
  end

  def getEntries
    @entries
  end

  def glsData
    @glsData.join("\n")
  end

  def getGLSFileData
    @entries.map{
      |entry|
      ["\\newglossaryentry\{#{entry["label"]}\}\{",
       "\ttype=#{@type},",
       "\tname={#{entry["name"]}},",
       "\tdescription={#{entry["content"]}},",
       #"\tsort={#{entry["sort"]}}",
       "}\n"].join("\n")
    }
  end

  def getMonth(mm)
    return [ 0,
             "January", "Feburary", "March", "April",
             "May", "June", "July", "August",
             "September", "October", "November", "December"
             ][mm.to_i]
  end

  def getDateToStr(d)
    _date = d.split("-")
    year = _date[0].to_i
    month = getMonth(_date[1].to_i)
    day = _date[2].to_i
    if day == 0
      if month == 0
        return "Year #{year}"
      else
        return "#{month} #{year}"
      end
    else
      return "#{month} #{day}, #{year}"
    end
  end

  def parseIfDate(string)
    if /\d\d\d\-\d\d\-\d\d/.match(string)
      return getDateToStr(string)
    else
      string
    end
  end

  def getGLSEntries
    entries = File.open(@file).read.split("\n").compact.uniq
    count = 0
    entries.map!{
      |entry|
      p entry
      count = count + 1
      fields = entry.split("\t")
      p fields
      find = fields[0]
      content = fields.length == 2 ? parseIfDate(fields[1]) : "not edited"

      substitute = fields[0].split("#").length == 2
      find = fields[0].split("#").first if fields[0].split("#").length == 2

      title = find

      title = fields[0].split("#").last if fields[0].split("#").length == 2


      label = @glsID + find #.upcase.gsub(/\W/,'-').gsub(/\-+/,'-')
      {
        "label" => label,
        "sort" => find.upcase.gsub(/\W/,'-').gsub(/\-+/,'-'),
        "type" => @type,
        "name" => parseIfDate(title),
        "content" => content,
        "find" => find.split("#").first,
        "replace" => substitute ? "#{find.gsub(title, "")}\\gls\{#{label}\}" : "\\gls\{#{label}\}"
      }
    }
  end

  def getGLSType
    type = File.split(@file).last.gsub(File.extname(@file), "")
    return type
  end

  def process(body)
    for entry in @entries
			p entry
      body.gsub!(Regexp.new(entry["find"]), entry["replace"])
    end
  end
end

class GlossaryIndex
  def initialize(dir = false)
    @basePath = dir == false ? File.expand_path(".") : dir
    @dirGLS = File.join(@basePath, "TeX_gls")
    raise "GLOSSARY_DIR_NOT_FOUND" if !Dir.exist?(@dirGLS)
    @dirTex = File.join(@basePath, "TeX_files")
    $logger.debug "TEX_FILES => #{@dirTex}"
    raise "TEX_DIR_NOT_FOUND" if !Dir.exist?(@dirGLS)
    @filesGLS = getFiles(@dirGLS, ".txt")
    @filesTEX = getFiles(@dirTex, ".tex")
    @filesData = getFilesData
  end

  def save
    out = File.open(File.join(@basePath, "body.tex"), "w+")
    out.puts @filesData
    out.close
  end

  def process
    _acronym = Acronym.new
    _acronym.save
    _acronym.process(@filesData)
    _index = Index.new(@basePath)
    _index.process(@filesData)
    @filesGLS.each{
      |file|
      _gls = GlossaryItems.new(file)
      _gls.save()
      _gls.process(@filesData)
    }
  end

  def getFilesData
    data = []
    _endnotes = EndNotes.new
    @filesTEX.each{
      |file|
      data << "\% From File: #{file}\n\%\n"
      data << _endnotes.process(file, File.open(file).read)
    }
    data = data.join("\n")
  end

  def getFiles(dir, ext)
    files = Dir.entries(dir)
    files.select!{
      |file|
      File.extname(file) ==  ext and !["acronym.txt"].include? file
    }
    files.map!{
      |file|
      File.join(dir, file)
    }
    files.uniq.compact
  end
end

options = ARGV

if options.length < 2
  gls = GlossaryIndex.new()
  gls.process()
  gls.save()
else
  if options.include? "-init" or options.include? "-i"
    puts "Setting up tex project ..."
    system("robocopy C:\\Code\\ruby\\textool\\init . /E > nul")
    system("git init > nul")
  end
  if options.include? "-date" or options.include? "-d"
    date = FindDates.new()
    date.save()
    exit!()
  end
  if options.include? "-find" or options.include? "-f"
    regexp = Regexp.compile(options.select{|a| a.include? "/"}[0][1..-2], Regexp::MULTILINE | Regexp::IGNORECASE)
    tex = options.select{|a| a.include? ".tex"}
    puts "Searching with #{regexp} in #{tex}"
    tex.each{
      |file|
      puts File.open(File.join(File.expand_path("."), file)).read.scan(regexp)
    }
  end
end

p ARGV

basePath = Dir.pwd()
FileUtils.cp(File.join(basePath, "TeX_main", "main.tex"), basePath)

if ARGV.include? "commit" or ARGV.include? "save"
  puts "Committing changes...".colorize(:yellow)
  system("git add .")
  system("git commit -m \"commit before build\"")
end

puts "Compiling Tex (1)".colorize(:yellow)
system("xelatex.exe -quiet -synctex=1 -interaction=nonstopmode \"main\"")
puts "ReBuilding index".colorize(:yellow)
system("makeindex.exe \"main\".tex")
puts "ReBuilding glossaries".colorize(:yellow)
system("makeglossaries.exe \"main\"")
puts "Compiling Tex (2)".colorize(:yellow)
system("xelatex.exe -quiet -synctex=1 -interaction=nonstopmode \"main\"")
puts "Compiling Tex (3)".colorize(:yellow)
system("xelatex.exe -quiet -synctex=1 -interaction=nonstopmode \"main\"")
puts "Preview PDF".colorize(:yellow)
system("SumatraPDF.exe main.pdf")
