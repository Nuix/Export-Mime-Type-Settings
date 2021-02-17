script_directory = File.dirname(__FILE__)
require File.join(script_directory,"Nx.jar")
java_import "com.nuix.nx.NuixConnection"
java_import "com.nuix.nx.LookAndFeelHelper"
java_import "com.nuix.nx.dialogs.ChoiceDialog"
java_import "com.nuix.nx.dialogs.TabbedCustomDialog"
java_import "com.nuix.nx.dialogs.CommonDialogs"
java_import "com.nuix.nx.dialogs.ProgressDialog"
java_import "com.nuix.nx.dialogs.ProcessingStatusDialog"
java_import "com.nuix.nx.digest.DigestHelper"
java_import "com.nuix.nx.controls.models.Choice"

LookAndFeelHelper.setWindowsIfMetal
NuixConnection.setUtilities($utilities)
NuixConnection.setCurrentNuixVersion(NUIX_VERSION)

load File.join(script_directory,"MimeTypeSettingsHelper.rb")

choice_as_json = "As JSON"
choice_as_csv = "As CSV"
choice_both = "Both"
export_format_choices = [
	choice_as_json,choice_as_csv,choice_both
]

dialog = TabbedCustomDialog.new("Mime Type Settings Export")

main_tab = dialog.addTab("main_tab","Main")
main_tab.appendDirectoryChooser("output_directory","Output Directory")
main_tab.appendComboBox("export_formats","Export Format(s)",export_format_choices)

dialog.validateBeforeClosing do |values|
	if values["output_directory"].nil? || values["output_directory"].strip.empty?
		CommonDialogs.showWarning("Please select a value for 'Ouput Directory'")
	end

	next true
end

dialog.display
if dialog.getDialogResult == true
	values = dialog.toMap

	output_directory = values["output_directory"]
	export_as_json = (values["export_formats"] == choice_as_json || values["export_formats"] == choice_both)
	export_as_csv = (values["export_formats"] == choice_as_csv || values["export_formats"] == choice_both)


	ProgressDialog.forBlock do |pd|
		MimeTypeSettingsHelper.on_message_logged do |message|
			pd.setMainStatusAndLogIt(message)
		end
	
		pd.setMainStatusAndLogIt("Ensuring output directory exists...")
		java.io.File.new(output_directory).mkdirs

		if export_as_json
			MimeTypeSettingsHelper.save_json_files(output_directory,$current_case)
		end

		if export_as_csv
			MimeTypeSettingsHelper.save_csv_files(output_directory,$current_case)
		end

		pd.setCompleted
	end
end