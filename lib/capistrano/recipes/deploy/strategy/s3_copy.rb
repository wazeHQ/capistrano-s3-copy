require 'capistrano/recipes/deploy/strategy/copy'
require 'erb'


module Capistrano
  module Deploy
    module Strategy
      class S3Copy < Copy

        def initialize(config={})
          super(config)

          s3cmd_vars = []
          ["aws_access_key_id", "aws_secret_access_key"].each do |var|
            value = configuration[var.to_sym]
            raise Capistrano::Error, "Missing configuration[:#{var}] setting" if value.nil?
            s3cmd_vars << "#{var.upcase}=#{value}"
          end
          @aws_environment = s3cmd_vars.join(" ")

          @bucket_name = configuration[:aws_releases_bucket]
          raise Capistrano::Error, "Missing configuration[:aws_releases_bucket]" if @bucket_name.nil?
        end

        def check!
          super.check do |d|
            d.local.command("s3cmd")
            d.remote.command("s3cmd")
          end
        end

        # Distributes the file to the remote servers
        def distribute!
          package_path = filename
          package_name = File.basename(package_path)
          s3_push_cmd = "#{aws_environment} s3cmd put #{bucket_name}:#{release_folder}/#{package_name} #{package_path} x-amz-server-side-encryption:AES256 2>&1"

          if configuration.dry_run
            logger.debug s3_push_cmd
          else
            system(s3_push_cmd)
            raise Capistrano::Error, "shell command failed with return code #{$?}" if $? != 0
          end

          run "#{aws_environment} s3cmd get s3://#{bucket_name}/#{release_folder}/#{package_name} #{remote_filename} 2>&1"
          run "cd #{configuration[:releases_path]} && #{decompress(remote_filename).join(" ")} && rm #{remote_filename}"
          logger.debug "done!"

          build_aws_install_script
        end

        def build_aws_install_script
          template_text = configuration[:aws_install_script]
          template_text = File.read(File.join(File.dirname(__FILE__), "aws_install.sh.erb")) if template_text.nil?
          template_text = template_text.gsub("\r\n?", "\n")
          template = ERB.new(template_text, nil, '<>-')
          output = template.result(self.binding)
          local_output_file = File.join(copy_dir, "aws_install.sh")
          logger.debug "File name: #{local_output_file}"
          File.open(local_output_file, "w") do  |f|
            f.write(output)
          end
          configuration[:s3_copy_aws_install_cmd] = "#{aws_environment} s3cmd put #{bucket_name}:#{release_folder}/aws_install.sh #{local_output_file} x-amz-server-side-encryption:AES256 2>&1"
        end

        def binding
          super
        end

        def aws_environment
          @aws_environment
        end

        def bucket_name
          @bucket_name
        end

        def release_folder
          release_folder_name || rails_env
        end
      end
    end
  end
end
