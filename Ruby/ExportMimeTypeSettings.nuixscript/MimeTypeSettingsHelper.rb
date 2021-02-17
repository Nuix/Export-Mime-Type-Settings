# Class to assist in extracting mime type settings from BatchLoadDetails
class MimeTypeSettingsHelper
	class << self
		# Names in batch load details don't quite line up with settings accepted by processor
		# so here we define some naming conversions
		SETTING_NAME_CONVERSION = {
			"Process embedded" => "processEmbedded",
			"Process images" => "processImages",
			"Text processing mode" => "processText",
			"Store binary" => "storeBinary",
			"Process named entities" => "processNamedEntities",
		}

		# Mime types are partially encoded in batch load details so we use this method
		# to decode them
		def remove_encoded_chars(input)
			return input
				.gsub(/\#45/,"-")
				.gsub(/\#46/,".")
				.gsub(/\#47/,"/")
		end

		# This method uses the previously defined SETTING_NAME_CONVERSION hash to convert
		# names to those recognized by Processor.setMimeTypeProcessingSettings
		def fix_setting_name(input)
			return SETTING_NAME_CONVERSION[input]
		end

		# Batch load details may refer to disabled mime types individually or entire kinds
		# se we have a method to expand kind references to all the types with that kind
		def expand_kind_reference(input)
			if input =~ /^kind:/
				kind_name = input.gsub(/^kind:(.*)/,"\1")
				return $utilities
					.getItemTypeUtility
					.getAllTypes
					.select{ |t|t.getKind.getName == kind_name }
					.map{ |t| t.getName }
			else
				return Array(input)
			end
		end

		# This is the method that will actually extract the mime type settings from the batch load details
		# into a form which is more usable as processor settings
		# Example Result Hash
		#  {
		#    "application/vnd.ms-windows-event-log": {
		#      "enabled": true,
		#      "processEmbedded": false,
		#      "storeBinary": true,
		#      "processImages": true,
		#      "textStrip": true,
		#      "processText": false,
		#      "processNamedEntities": true
		#    },
		#    "filesystem/x-ntfs-logfile": {
		#      "enabled": true,
		#      "processImages": true,
		#      "processNamedEntities": true,
		#      "storeBinary": true,
		#      "processEmbedded": false,
		#      "textStrip": false,
		#      "processText": true
		#    },
		#    "application/vnd.ms-windows-event-logx": {
		#      "enabled": false,
		#    },
		#    ... ETC ...
		#  }
		def get_mime_type_settings(batch_load_detail)
			# Define a hash which when a missing key is accessed with default the missing
			# value to be an inner hash with a default "enabled" state of true
			mime_type_settings = Hash.new{ |h,k|h[k] = {"enabled"=>true} }
			# Iterate the data processing settings
			batch_load_detail.getDataProcessingSettings.each do |k,v|
				# Skip keys which don't appear to be mime type settings
				next unless k =~ /^Mime type settings/
				# Split on periods into multiple chunks
				# Chunk 0 = Mime type settings
				# Chunk 1 = Mime type name with encoded chars
				# Chunk 2 = Setting name which needs conversion
				key_parts = k.split(".")
				# Take the mime type name portion and decode the encoded characters
				mime_type = remove_encoded_chars(key_parts[1])
				# Take the setting name portion and convert to name recognized by Processor.setMimeTypeProcessingSettings
				setting = fix_setting_name(key_parts[2])
				# Convert string boolean values to actual booleans
				value = v
				if value == "true"
					value = true
				elsif value == "false"
					value = false
				end
				# Processor.setMimeTypeProcessingSettings has 2 text settings:
				# "processText" and "textStrip"
				# While batch load details records this as "Text processing mode" with values:
				# "strip_text" and "skip_text" and "process_text"
				# So we need some extra logic to split this out into two settings
				if setting == "processText" && value == "text_strip"
					case value
					when "text_strip"
						mime_type_settings[mime_type]["textStrip"] = true
						mime_type_settings[mime_type]["processText"] = false
					when "skip_text"
						mime_type_settings[mime_type]["textStrip"] = false
						mime_type_settings[mime_type]["processText"] = false
					when "process_text"
						mime_type_settings[mime_type]["textStrip"] = false
						mime_type_settings[mime_type]["processText"] = true
					end
				else
					mime_type_settings[mime_type][setting] = value
				end
			end

			# Batch load details represents entirely disabled types differently than the API so
			# we need a little extra logic to mend this in as desired
			batch_load_detail.getDataSettings["Disabled mime types"].split(",").each do |mime_type|
				# An entry may be either a mime type name or entire kind (ex kind:email) so
				# we need logic to expand kind references to all the mime types with that kind
				expand_kind_reference(mime_type).each do |expanded_mime_type|
					mime_type_settings[expanded_mime_type]["enabled"] = false
				end
			end

			# We should have our result now, so return it
			return mime_type_settings
		end

		def on_message_logged(&block)
			@message_logged_callback = block
		end

		def log(message)
			if !@message_logged_callback.nil?
				@message_logged_callback.call(message)
			else
				puts message
			end
		end

		def save_json_file(file_path,batch_load_detail)
			require 'json'
			# Extract mime type settings from batch load detail
			mime_type_settings = MimeTypeSettingsHelper.get_mime_type_settings(batch_load_detail)
			log("Saving #{file_path}")
			File.open(file_path,"w:utf-8") do |json_file|
				json_file.puts(JSON.pretty_generate(mime_type_settings))
			end
		end

		def save_json_files(directory,nuix_case=$current_case)
			if nuix_case.nil?
				raise "nuix_case/$current_case cannot be nil!"
			end

			nuix_case.getBatchLoads.each do |batch_load_detail|
				file_path = File.join(directory,"BatchLoad_#{batch_load_detail.getBatchId}_MimeTypeSettings.json")
				save_json_file(file_path,batch_load_detail)
			end
		end

		def save_csv_files(directory,nuix_case=$current_case)
			if nuix_case.nil?
				raise "nuix_case/$current_case cannot be nil!"
			end

			require 'csv'
			mime_type_setting_keys = [
				"enabled",
				"storeBinary",
				"processNamedEntities",
				"processEmbedded",
				"processImages",
				"processText",
			]

			$current_case.getBatchLoads.each do |batch_load_detail|
				file_path = File.join(directory,"BatchLoad_#{batch_load_detail.getBatchId}_MimeTypeSettings.csv")
				
				CSV.open(file_path,"w:utf-8") do |csv|
					csv << [
						"Mime Type",
					] + mime_type_setting_keys

					case_name = $current_case.getName

					# Extract mime type settings from batch load detail
					mime_type_settings = MimeTypeSettingsHelper.get_mime_type_settings(batch_load_detail)

					log("Saving #{file_path}")
					mime_type_settings.keys.sort.each do |mime_type|
						settings = mime_type_settings[mime_type]
						values = [
							case_name,
							batch_load_detail.getBatchId,
							mime_type,
						]

						values += mime_type_setting_keys.map{|key| settings[key]}
						csv << values
					end
				end
			end
		end

	end
end