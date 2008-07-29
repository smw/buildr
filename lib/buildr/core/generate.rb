# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with this
# work for additional information regarding copyright ownership.  The ASF
# licenses this file to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
# License for the specific language governing permissions and limitations under
# the License.


require 'buildr/java/pom'


module Buildr
  module Generate #:nodoc:

    task "generate" do
      script = nil 
      choose do |menu|
        menu.header = "To use Buildr you need a buildfile. Do you want me to create one?"

        menu.choice("From maven2 pom file") { script = Generate.from_maven2_pom(true).join("\n") } if File.exists?("pom.xml")
        menu.choice("From directory structure") { script = Generate.from_directory(true).join("\n") }
        menu.choice("Skip") { }
      end
       
      if script    
        buildfile = File.expand_path(Buildr::Application::DEFAULT_BUILDFILES.first)
        File.open(buildfile, "w") { |file| file.write script }
        puts "Created #{buildfile}"
      end        
    end

    class << self


      HEADER = "# Generated by Buildr #{Buildr::VERSION}, change to your liking\n\n"


      def from_directory(root = false)
        name = File.basename(Dir.pwd)
        if root
          script = HEADER.split("\n")
          header = <<-EOF
# Version number for this release
VERSION_NUMBER = "1.0.0"
# Version number for the next release
NEXT_VERSION = "1.0.1"
# Group identifier for your projects
GROUP = "#{name}"
COPYRIGHT = ""

# Specify Maven 2.0 remote repositories here, like this:
repositories.remote << "http://www.ibiblio.org/maven2/"

desc "The #{name.capitalize} project"
define "#{name}" do

  project.version = VERSION_NUMBER
  project.group = GROUP
  manifest["Implementation-Vendor"] = COPYRIGHT
EOF
          script += header.split("\n")
        else
          script = [ %{define "#{name}" do} ]
        end
        script <<  "  compile.with # Add classpath dependencies" if File.exist?("src/main/java")
        script <<  "  resources" if File.exist?("src/main/resources")
        script <<  "  test.compile.with # Add classpath dependencies" if File.exist?("src/test/java")
        script <<  "  test.resources" if File.exist?("src/test/resources")
        if File.exist?("src/main/webapp")
          script <<  "  package(:war)"
        elsif File.exist?("src/main/java")
          script <<  "  package(:jar)"
        end
        dirs = FileList["*"].exclude("src", "target", "report").
          select { |file| File.directory?(file) && File.exist?(File.join(file, "src")) }
        unless dirs.empty?
          script << ""
          dirs.sort.each do |dir|
            Dir.chdir(dir) { script << from_directory.flatten.map { |line| "  " + line } << "" }
          end
        end
        script << "end"
        script.flatten
      end

      def from_maven2_pom(root = false)
        pom = Buildr::POM.load('pom.xml')
        project = pom.project

        artifactId = project['artifactId'].first
        description = project['name'] || "The #{artifactId} project"
        project_name = File.basename(Dir.pwd)

        if root
          script = HEADER.split("\n")

          settings_file = ENV["M2_SETTINGS"] || File.join(ENV['HOME'], ".m2/settings.xml")
          settings = XmlSimple.xml_in(IO.read(settings_file)) if File.exists?(settings_file)

          if settings
            proxy = settings['proxies'].first['proxy'].find { |proxy|
              proxy["active"].nil? || proxy["active"].to_s =~ /true/
            } rescue nil
            
            if proxy
              url = %{#{proxy["protocol"].first}://#{proxy["host"].first}:#{proxy["port"].first}}
              exclude = proxy["nonProxyHosts"].to_s.gsub("|", ",") if proxy["nonProxyHosts"]
              script << "options.proxy.http = '#{url}'"
              script << "options.proxy.exclude << '#{exclude}'" if exclude
              script << ''
              # In addition, we need to use said proxies to download artifacts.
              Buildr.options.proxy.http = url
              Buildr.options.proxy.exclude << exclude if exclude
            end
          end

          repositories = project["repositories"].first["repository"].select { |repository|
            legacy = repository["layout"].to_s =~ /legacy/
            !legacy
          } rescue nil
          repositories = [{"name" => "Standard maven2 repository", "url" => "http://www.ibiblio.org/maven2/"}] if repositories.nil? || repositories.empty?
          repositories.each do |repository|
            name, url = repository["name"], repository["url"]
            script << "# #{name}"
            script << "repositories.remote << '#{url}'"
            # In addition we need to use said repositores to download artifacts.
            Buildr.repositories.remote << url.to_s
          end
          script << ""
        else
          script = []
        end

        script << "desc '#{description}'"
        script << "define '#{project_name}' do"

        groupId = project['groupId']
        script << "  project.group = '#{groupId}'" if groupId

        version = project['version']
        script << "  project.version = '#{version}'" if version

        #get plugins configurations
        plugins = project['build'].first['plugins'].first['plugin'] rescue {}
        if plugin
          compile_plugin = plugins.find{|pl| (pl['groupId'].nil? or pl['groupId'].first == 'org.apache.maven.plugins') and pl['artifactId'].first == 'maven-compiler-plugin'}
          if compile_plugin
            source = compile_plugin.first['configuration'].first['source'] rescue nil
            target = compile_plugin.first['configuration'].first['target'] rescue nil

            script << "  compile.options.source = '#{source}'" if source
            script << "  compile.options.target = '#{target}'" if target
          end
        end

        compile_dependencies = pom.dependencies
        dependencies = compile_dependencies.sort.map{|d| "'#{d}'"}.join(', ')
        script <<  "  compile.with #{dependencies}" unless dependencies.empty?

        test_dependencies = (pom.dependencies(['test']) - compile_dependencies).reject{|d| d =~ /^junit:junit:jar:/ }
        #check if we have testng
        use_testng = test_dependencies.find{|d| d =~ /^org.testng:testng:jar:/}
        if use_testng
          script <<  "  test.using :testng"
          test_dependencies = pom.dependencies(['test']).reject{|d| d =~ /^org.testng:testng:jar:/ }
        end

        test_dependencies = test_dependencies.sort.map{|d| "'#{d}'"}.join(', ')
        script <<  "  test.with #{test_dependencies}" unless test_dependencies.empty?

        packaging = project['packaging'] ? project['packaging'].first : 'jar'
        if %w(jar war).include?(packaging)
          script <<  "  package :#{packaging}, :id => '#{artifactId}'"
        end

        modules = project['modules'].first['module'] rescue nil
        if modules
          script << ""
          modules.each do |mod|
            chdir(mod) { script << from_maven2_pom.flatten.map { |line| "  " + line } << "" }
          end
        end
        script << "end"
        script.flatten
      end
       
    end
  end
end 
