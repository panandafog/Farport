# Validate real deliver option definitions without executing a transport action.
require "fastlane"
require "deliver"
require "tmpdir"

Dir.mktmpdir("farport-fastlane-check-") do |dir|
  ENV["ASC_KEY_PATH"] = File.join(dir, "fake.p8")
  File.write(ENV["ASC_KEY_PATH"], "offline test key; never used for authentication")
  ENV["ASC_KEY_ID"] = "TEST"
  ENV["ASC_ISSUER_ID"] = "TEST"
  ENV["ASC_BUNDLE_ID"] = "com.panandafog.harbor"
  ["IOS", "MAC_OS"].each do |platform|
    ENV["ASC_PLATFORM"] = platform
    ENV["ASC_BINARY_PATH"] = File.join(dir, platform == "IOS" ? "check.ipa" : "check.pkg")
    File.write(ENV["ASC_BINARY_PATH"], "offline validation only")
    verifier = Object.new
    def verifier.opt_out_usage; end
    def verifier.lane(name, &body)
      raise "Unexpected lane" unless name == :upload_binary
      instance_eval(&body)
    end
    def verifier.upload_to_app_store(**options)
      raise "Submission enabled" unless options[:submit_for_review] == false
      raise "Unexpected metadata update" unless options[:skip_metadata] && options[:skip_screenshots] && options[:skip_app_version_update]
      raise "Release settings changed" if options.key?(:automatic_release) || options.key?(:phased_release)
      FastlaneCore::Configuration.create(Deliver::Options.available_options, options)
    end
    verifier.instance_eval(File.read("fastlane/Fastfile"), "fastlane/Fastfile")
    puts "#{platform}: deliver options valid; transport was not executed."
  end
end
