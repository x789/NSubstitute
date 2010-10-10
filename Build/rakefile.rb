require 'rake/clean'
require File.expand_path('lib/examples_to_code.rb', File.dirname(__FILE__))
require 'FileUtils'
require 'date'

DOT_NET_PATH = "#{ENV["SystemRoot"]}\\Microsoft.NET\\Framework\\v3.5"
NUNIT_EXE = "../ThirdParty/NUnit/bin/net-2.0/nunit-console.exe"
NUPACK_EXE = "../ThirdParty/NuPack/NuPack.exe"
SOURCE_PATH = "../Source"
OUTPUT_PATH = "../Output"

ENV["config"] = "Debug" if ENV["config"].nil?
CONFIG = ENV["config"]

CLEAN.include(OUTPUT_PATH)

task :default => ["clean", "all"]
task :all => [:compile, :test, :specs]
desc "Update assembly versions, build, generate docs and create directory for packaging"
task :deploy => [:version_assemblies, :default, :generate_docs, :package, :nupack]
  
desc "Build solutions using MSBuild"
task :compile do
    solutions = FileList["#{SOURCE_PATH}/**/*.sln"].exclude(/\.2010\./)
    solutions.each do |solution|
    sh "#{DOT_NET_PATH}/msbuild.exe /p:Configuration=#{CONFIG} #{solution}"
    end
end

desc "Runs tests with NUnit"
task :test => [:compile] do
    tests = FileList["#{OUTPUT_PATH}/**/NSubstitute.Specs.dll"].exclude(/obj\//)
    sh "#{NUNIT_EXE} #{tests} /nologo /exclude=Pending /xml=#{OUTPUT_PATH}/UnitTestResults.xml"
end

desc "Run acceptance specs with NUnit"
task :specs => [:compile] do
    tests = FileList["#{OUTPUT_PATH}/**/NSubstitute.Acceptance.Specs.dll"].exclude(/obj\//)
    sh "#{NUNIT_EXE} #{tests} /nologo /exclude=Pending /xml=#{OUTPUT_PATH}/SpecResults.xml"
end

desc "Runs pending acceptance specs with NUnit"
task :pending => [:compile] do
    acceptance_tests = FileList["#{OUTPUT_PATH}/**/NSubstitute.Acceptance.Specs.dll"].exclude(/obj\//)
    sh "#{NUNIT_EXE} #{acceptance_tests} /nologo /include=Pending /xml=#{OUTPUT_PATH}/PendingSpecResults.xml"
end

desc "Generates documentation for the website"
task :generate_docs => [:all, :check_examples] do
    output = File.expand_path("#{OUTPUT_PATH}/nsubstitute.github.com", File.dirname(__FILE__))
    FileUtils.cd "../Source/Docs" do
        sh "jekyll \"#{output}\""
    end
end

desc "Compile and test code from examples from last NSubstitute build"
task :check_examples => [:generate_code_examples, :compile_code_examples, :test_examples]

task :generate_code_examples do
    examples_to_code = ExamplesToCode.create
    examples_to_code.convert("../Source/Docs/", "#{OUTPUT_PATH}/CodeFromDocs")
    examples_to_code.convert("../Source/Docs/help/_posts/", "#{OUTPUT_PATH}/CodeFromDocs")
    examples_to_code.convert("../", "#{OUTPUT_PATH}/CodeFromDocs")
end

task :compile_code_examples => [:generate_code_examples] do
    #Copy references to documentation directory
	output_base_path = "#{OUTPUT_PATH}/#{CONFIG}"
    output_doc_path = "#{OUTPUT_PATH}/CodeFromDocs"
    references = %w(NSubstitute.dll nunit.framework.dll).map do |x| 
        "#{output_base_path}/NSubstitute.Specs/#{x}"
    end
    FileUtils.cp references, output_doc_path

    #Compile
    FileUtils.cd output_doc_path do
        sh "#{DOT_NET_PATH}/csc.exe /target:library /out:\"NSubstitute.Samples.dll\" /reference:\"nunit.framework.dll\" /reference:\"NSubstitute.dll\" *.cs"
    end
end

task :test_examples => [:compile_code_examples] do
    tests = FileList["#{OUTPUT_PATH}/**/NSubstitute.Samples.dll"].exclude(/obj\//)
    sh "#{NUNIT_EXE} #{tests} /nologo /exclude=Pending /xml=#{OUTPUT_PATH}/DocResults.xml"
end

task :version_assemblies => [:get_build_number] do 
	assembly_info_files = "#{SOURCE_PATH}/**/AssemblyInfo.cs"

	assembly_info_template_replacements = [
		['0.0.0.0', @@build_number]
	]
	
	Dir.glob(assembly_info_files).each do |file|
	  content = File.new(file,'r').read
	  assembly_info_template_replacements.each { |info| content.gsub!(/#{info[0]}/, info[1]) }
	  File.open(file, 'w') { |fw| fw.write(content) }
	end
end

desc "Gets build number based on git tags and commit."
task :get_build_number do
 	version_info = get_build_version
	@@build_number = "#{version_info[1]}.#{version_info[2]}.#{version_info[3]}.#{version_info[4]}"
end

def get_build_version
  /v(\d+)\.(\d+)\.(\d+)\-(\d+)/.match(`git describe --tags --long --match v*`.chomp)
end


desc "Packages up assembly"
task :package => [:version_assemblies, :all, :check_examples] do
	output_base_path = "#{OUTPUT_PATH}/#{CONFIG}"
	dll_path = "#{output_base_path}/NSubstitute"
	deploy_path = "#{output_base_path}/NSubstitute-#{@@build_number}"

    mkdir_p deploy_path
	cp Dir.glob("#{dll_path}/*.{dll,xml}"), deploy_path

	cp "../README.markdown", "#{deploy_path}/README.txt"
	cp "../LICENSE.txt", "#{deploy_path}"
	cp "../CHANGELOG.txt", "#{deploy_path}"
    tidyUpTextFileFromMarkdown("#{deploy_path}/README.txt")
end

desc "Create NuPack package"
task :nupack => [:package] do
	output_base_path = "#{OUTPUT_PATH}/#{CONFIG}"
	dll_path = "#{output_base_path}/NSubstitute"
	deploy_path = "#{output_base_path}/NSubstitute-#{@@build_number}"
	nupack_path = "#{output_base_path}/nupack/#{@@build_number}"
	nupack_lib_path = "#{output_base_path}/nupack/#{@@build_number}/lib/35"

    #Ensure nupack path exists
    mkdir_p nupack_lib_path

    #Copy binaries into lib path
    cp Dir.glob("#{dll_path}/*.{dll,xml}"), nupack_lib_path

    #Copy nuspec and *.txt docs into package root
    cp Dir.glob("#{deploy_path}/*.txt"), nupack_path
    cp "NSubstitute.nuspec", nupack_path
    updateNuspec("#{nupack_path}/NSubstitute.nuspec")

    #Build package
    full_path_to_nupack_exe = File.expand_path(NUPACK_EXE, File.dirname(__FILE__))
    nuspec = File.expand_path("#{nupack_path}/NSubstitute.nuspec", File.dirname(__FILE__))
    FileUtils.cd "#{output_base_path}/nupack" do
        sh "#{full_path_to_nupack_exe} #{nuspec}"
    end
end

def tidyUpTextFileFromMarkdown(file)
    text = File.read(file)
    File.open(file, "w") { |f| f.write( stripHtmlComments(text) ) }
end

def stripHtmlComments(text)
    startComment = "<!--"
    endComment = "-->"

    indexOfStart = text.index(startComment)
    indexOfEnd = text.index(endComment)
    return text if indexOfStart.nil? or indexOfEnd.nil?

    text[indexOfStart..(indexOfEnd+endComment.length-1)] = ""
    return stripHtmlComments(text)
end

def updateNuspec(file)
    text = File.read(file)
    modified_date = DateTime.now.rfc3339
    text.gsub! /<version>.*?<\/version>/, "<version>#{@@build_number}</version>"
    text.gsub! /<modified>.*?<\/modified>/, "<modified>#{modified_date}</modified>"
    File.open(file, 'w') { |f| f.write(text) }
end
