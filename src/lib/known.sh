# shellcheck shell=bash
#
# Programs whose file types are known without asking.
#
# The bottle's registry is asked first (scan.py): whatever an installer
# registered there is what Windows would open. This table is for programs
# that registered nothing, like portable installs or copied folders.

# Format: <pattern>|<ext>[=<switch>] ...
#
# The pattern matches the program's Windows path, lowercased, with / for \.
# A switch goes in front of the file, as in `OUTLOOK.EXE /f "file.msg"`.
BO_KNOWN_PROGRAMS=(
	# Microsoft Office
	"*/winword.exe|doc docx docm dot dotx dotm rtf odt"
	"*/excel.exe|xls xlsx xlsm xlsb xlt xltx xltm xlam xla csv ods"
	"*/powerpnt.exe|ppt pptx pptm pot potx potm pps=/s ppsx=/s ppsm=/s ppa ppam odp"
	"*/outlook.exe|msg=/f oft=/t eml=/eml vcf=/v ics=/ical vcs=/vcal"
	"*/msaccess.exe|accdb accde accdr accdt mdb mde"
	"*/mspub.exe|pub"
	"*/visio.exe|vsd vsdx vsdm vss vssx vssm vst vstx vstm"
	"*/winproj.exe|mpp mpt"
	"*/onenote.exe|one onepkg onetoc2"

	# Music
	"*/fl64.exe|flp fsc fst"
	"*/fl.exe|flp fsc fst"
	"*/ableton live *.exe|als alc adg"
	"*/cubase*.exe|cpr"
	"*/nuendo*.exe|npr"
	"*/studio one.exe|song"
	"*/reaper.exe|rpp"
	"*/reason.exe|reason"
	"*/adobe audition.exe|sesx"
	"*/guitarpro*.exe|gp gpx gp5 gp4 gp3"
	"*/sibelius.exe|sib"
	"*/finale.exe|musx mus"
	"*/foobar2000.exe|mp3 flac ogg opus m4a wav ape wv"

	# Images and design
	"*/photoshop.exe|psd psb"
	"*/photoshopelementseditor.exe|psd pse"
	"*/illustrator.exe|ai"
	"*/indesign.exe|indd indt idml"
	"*/lightroom.exe|lrcat"
	"*/animate.exe|fla"
	"*/affinity*/photo*.exe|afphoto"
	"*/affinity*/designer*.exe|afdesign"
	"*/affinity*/publisher*.exe|afpub"
	"*/clipstudiopaint.exe|clip"
	"*/coreldrw.exe|cdr"
	"*/paintdotnet.exe|pdn"
	"*/sai.exe|sai"
	"*/sai2.exe|sai2"

	# 3D and CAD
	"*/sketchup.exe|skp"
	"*/acad.exe|dwg dxf dwt"
	"*/acadlt.exe|dwg dxf dwt"
	"*/rhino.exe|3dm"
	"*/3dsmax.exe|max"
	"*/sldworks.exe|sldprt sldasm slddrw"
	"*/x2.exe|pcbdoc schdoc prjpcb"

	# Video
	"*/afterfx.exe|aep"
	"*/adobe premiere pro.exe|prproj"
	"*/vegas*.exe|veg"

	# Everything else
	"*/acrobat.exe|pdf"
	"*/acrord32.exe|pdf"
	"*/notepad++.exe|txt log"
	"*/7zfm.exe|7z zip rar"
	"*/winrar.exe|rar zip 7z"
)

# Types for extensions the system does not know.
#
# Format: <ext>|<MIME type>|<description>|<magic>|<generic icon>|<flags>
#
# <magic>: string:<text> or big32:<hex>, matched at offset 0.
# <flags>: "own" defines the type even where the system already uses the
# extension for something else. For example, .mpp is Musepack audio there, not
# a Project file. The magic tells the two apart.
BO_KNOWN_TYPES=(
	# Office
	"ppa|application/x-ms-powerpoint-addin|PowerPoint add-in||x-office-presentation|"
	"msg|application/vnd.ms-outlook|Outlook message||x-office-document|"
	"oft|application/x-ms-outlook-template|Outlook template||x-office-document|"
	"accdb|application/x-ms-access-database|Access database||x-office-spreadsheet|"
	"accde|application/x-ms-access-database|Access database||x-office-spreadsheet|"
	"accdr|application/x-ms-access-database|Access database||x-office-spreadsheet|"
	"accdt|application/x-ms-access-template|Access template||x-office-spreadsheet|"
	"mde|application/x-ms-access-database|Access database||x-office-spreadsheet|"
	"mpp|application/vnd.ms-project|Project file|big32:0xd0cf11e0|x-office-spreadsheet|own"
	"mpt|application/x-ms-project-template|Project template||x-office-spreadsheet|"
	"one|application/onenote|OneNote section||x-office-document|"
	"onepkg|application/x-onenote-package|OneNote package||x-office-document|"
	"onetoc2|application/x-onenote-toc|OneNote table of contents||x-office-document|"

	# Music
	"flp|application/x-flstudio-project|FL Studio project|string:FLhd|audio-x-generic|"
	"fsc|application/x-flstudio-score|FL Studio score||audio-x-generic|"
	"fst|application/x-flstudio-preset|FL Studio preset|string:FLhd|audio-x-generic|own"
	"als|application/x-ableton-live-set|Ableton Live set||audio-x-generic|"
	"alc|application/x-ableton-live-clip|Ableton Live clip||audio-x-generic|"
	"adg|application/x-ableton-device-group|Ableton device group||audio-x-generic|"
	"cpr|application/x-cubase-project|Cubase project||audio-x-generic|"
	"npr|application/x-nuendo-project|Nuendo project||audio-x-generic|"
	"song|application/x-studio-one-song|Studio One song||audio-x-generic|"
	"rpp|application/x-reaper-project|REAPER project|string:<REAPER_PROJECT|audio-x-generic|"
	"reason|application/x-reason-song|Reason song||audio-x-generic|"
	"sesx|application/x-audition-session|Audition session||audio-x-generic|"
	"gp|application/x-guitar-pro|Guitar Pro tablature|big32:0x504b0304|audio-x-generic|own"
	"gpx|application/x-guitar-pro|Guitar Pro tablature|string:BCFS|audio-x-generic|own"
	"gp5|application/x-guitar-pro|Guitar Pro tablature||audio-x-generic|"
	"gp4|application/x-guitar-pro|Guitar Pro tablature||audio-x-generic|"
	"gp3|application/x-guitar-pro|Guitar Pro tablature||audio-x-generic|"
	"sib|application/x-sibelius-score|Sibelius score||audio-x-generic|"
	"musx|application/x-finale-score|Finale score||audio-x-generic|"
	"mus|application/x-finale-score|Finale score||audio-x-generic|"

	# Images and design
	"psb|application/x-photoshop-large-document|Photoshop large document||image-x-generic|"
	"pse|application/x-photoshop-elements|Photoshop Elements document||image-x-generic|"
	"indd|application/x-indesign-document|InDesign document||x-office-document|"
	"indt|application/x-indesign-template|InDesign template||x-office-document|"
	"idml|application/vnd.adobe.indesign-idml-package|InDesign markup||x-office-document|"
	"lrcat|application/x-lightroom-catalog|Lightroom catalog||image-x-generic|"
	"fla|application/x-adobe-animate|Animate document||video-x-generic|"
	"afphoto|application/x-affinity-photo|Affinity Photo document||image-x-generic|"
	"afdesign|application/x-affinity-designer|Affinity Designer document||image-x-generic|"
	"afpub|application/x-affinity-publisher|Affinity Publisher document||x-office-document|"
	"clip|application/x-clip-studio-paint|Clip Studio Paint file||image-x-generic|"
	"pdn|application/x-paintdotnet|Paint.NET image||image-x-generic|"
	"sai|application/x-paint-tool-sai|PaintTool SAI document||image-x-generic|"
	"sai2|application/x-paint-tool-sai2|PaintTool SAI document||image-x-generic|"

	# 3D and CAD
	"skp|application/vnd.sketchup.skp|SketchUp model||x-office-drawing|"
	"dwt|application/x-autocad-template|AutoCAD template||x-office-drawing|"
	"3dm|application/x-rhino-model|Rhino model||x-office-drawing|"
	"max|application/x-3ds-max-scene|3ds Max scene||x-office-drawing|"
	"sldprt|application/x-solidworks-part|SolidWorks part||x-office-drawing|"
	"sldasm|application/x-solidworks-assembly|SolidWorks assembly||x-office-drawing|"
	"slddrw|application/x-solidworks-drawing|SolidWorks drawing||x-office-drawing|"
	"pcbdoc|application/x-altium-pcb|Altium PCB||x-office-drawing|"
	"schdoc|application/x-altium-schematic|Altium schematic||x-office-drawing|"
	"prjpcb|application/x-altium-project|Altium project||x-office-drawing|"

	# Video
	"aep|application/x-after-effects-project|After Effects project||video-x-generic|"
	"prproj|application/x-premiere-project|Premiere Pro project||video-x-generic|"
	"veg|application/x-vegas-project|VEGAS project||video-x-generic|"
)

# bo_known_exts <windows path>
# BO_KNOWN: the extensions, space separated. BO_KNOWN_ARGS[ext]: the Windows
# argument template for those that need a switch.
BO_KNOWN=''
declare -A BO_KNOWN_ARGS=()

bo_known_exts() {
	local path="${1,,}" rule pattern entry ext
	path="${path//\\//}"
	BO_KNOWN=''
	BO_KNOWN_ARGS=()

	for rule in "${BO_KNOWN_PROGRAMS[@]}"; do
		pattern="${rule%%|*}"
		# shellcheck disable=SC2053  # the right-hand side is a pattern on purpose
		[[ $path == $pattern ]] || continue
		for entry in ${rule#*|}; do
			ext="${entry%%=*}"
			[[ " $BO_KNOWN " == *" $ext "* ]] && continue
			BO_KNOWN="${BO_KNOWN:+$BO_KNOWN }$ext"
			[[ $entry == *=* ]] && BO_KNOWN_ARGS[$ext]="${entry#*=} \"%1\""
		done
	done
	[[ -n $BO_KNOWN ]]
}

# bo_known_type <extension>
# BO_KT_MIME, _DESC, _MAGIC, _ICON and _OWN for an extension. Anything not in
# the table gets a type named after the extension and this program, so it
# cannot collide with a real one. Returns 1 for those.
BO_KT_MIME=''
BO_KT_DESC=''
BO_KT_MAGIC=''
BO_KT_ICON=''
BO_KT_OWN=0

declare -A BO_KT_INDEX=()

bo_known_type() {
	local ext="$1" entry e mime desc magic icon flags

	if (( ${#BO_KT_INDEX[@]} == 0 )); then
		for entry in "${BO_KNOWN_TYPES[@]}"; do
			BO_KT_INDEX[${entry%%|*}]="$entry"
		done
	fi

	if [[ -n ${BO_KT_INDEX[$ext]:-} ]]; then
		IFS='|' read -r e mime desc magic icon flags <<< "${BO_KT_INDEX[$ext]}"
		BO_KT_MIME="$mime"; BO_KT_DESC="$desc"
		BO_KT_MAGIC="$magic"; BO_KT_ICON="$icon"
		BO_KT_OWN=0
		[[ $flags == *own* ]] && BO_KT_OWN=1
		return 0
	fi

	BO_KT_MIME="application/x-bottles-opener-${ext}"
	BO_KT_DESC="${ext^^} file"
	BO_KT_MAGIC=''
	BO_KT_ICON='application-x-generic'
	BO_KT_OWN=0
	return 1
}
