local function GetSimfileString(path)

	local ssc, sm
	local files = FILEMAN:GetDirListing(path)

	for file in ivalues(files) do
		if file:find(".+%.ssc$") then
			-- Finding a .ssc file is preferable.
			-- If we find one, stop looking.
			ssc = file
			break
		elseif file:find(".+%.sm$") then
			-- Don't break if we find a .sm file first;
			-- there might still be a .ssc file waiting.
			sm = file
		end
	end

	-- if neither a .ssc nor a .sm file were found, bail now
	if not ssc and not sm then return end
	local filename = ssc or sm

	-- create a generic RageFile that we'll use to read the contents
	-- of the desired .ssc or .sm file
	local f = RageFileUtil.CreateRageFile()
	local contents

	-- the second argument here (the 1) signifies
	-- that we are opening the file in read-only mode
	if f:Open(path .. filename, 1) then
		contents = f:Read()
	end

	-- destroy the generic RageFile now that we have the contents
	f:destroy()
	return contents
end

-- ----------------------------------------------------------------
-- SOURCE: https://github.com/JonathanKnepp/SM5StreamParser

-- Which note types are counted as part of the stream?
local TapNotes = {1,2,4}


-- Utility function to replace regex special characters with escaped characters
local function regexEncode(var)
	return (var:gsub('%%', '%%%'):gsub('%^', '%%^'):gsub('%$', '%%$'):gsub('%(', '%%('):gsub('%)', '%%)'):gsub('%.', '%%.'):gsub('%[', '%%['):gsub('%]', '%%]'):gsub('%*', '%%*'):gsub('%+', '%%+'):gsub('%-', '%%-'):gsub('%?', '%%?'))
end

-- Parse the measures section out of our sim file
local function GetSimfileChartString(SimfileString, StepsType, Difficulty)
	local measuresString = nil

	if(SimfileString:match("#NOTEDATA")) then
		-- SSC File
		-- Loop through each chart in the SSC file
		for chart in SimfileString:gmatch("#NOTEDATA.-#NOTES:[^;]*") do
			-- Find the chart that matches our difficulty and game type
			if(chart:match("#STEPSTYPE:"..regexEncode(StepsType)) and chart:match("#DIFFICULTY:"..regexEncode(Difficulty))) then
				--Find just the notes and remove comments
				measuresString = chart:match("#NOTES:[\r\n]+([^;]*)\n?$"):gsub("\\[^\r\n]*","")
			end
		end
	else
		-- SM FILE
		-- Loop through each chart in the SM file
		for chart in SimfileString:gmatch("#NOTES[^;]*") do
			if(chart:match(regexEncode(StepsType)..":") and chart:match(regexEncode(Difficulty)..":")) then
				-- Find just the notes and remove comments
				measuresString = chart:match("#NOTES:.*:[\r\n]+(.*)\n?$"):gsub("//[^\r\n]*","")
			end
		end
	end

	return measuresString
end

-- Figure out which measures are considered a stream of notes
local function getStreamMeasures(measuresString, notesPerMeasure)
	-- Make our stream notes array into a string for regex
	local TapNotesString = ""
	for i, v in ipairs(TapNotes) do
		TapNotesString = TapNotesString .. v
	end

	-- Which measures are considered a stream?
	local streamMeasures = {}

	-- Keep track of the measure and its timing (8ths, 16ths, etc)
	local measureCount = 1
	local measureTiming = 0
	-- Keep track of the notes in a measure
	local measureNotes = {}

	-- How many

	-- Loop through each line in our string of measures
	for line in measuresString:gmatch("[^\r\n]+")
	do
		-- If we hit a comma or a semi-colon, then we've hit the end of our measure
		if(line:match("^[,;]%s*")) then
			-- Does this measure contain a stream of notes based on our notesPerMeasure global?
			if(#measureNotes >= notesPerMeasure) then
				local isStream = true

				-- What can the gap be between notes?
				local noteGapThreshold = measureTiming / notesPerMeasure

				-- Loop through our notes and see if they're placed correctly to be considered a stream (every 8th, every 16th, etc.)
				for i=1,(#measureNotes - 1),1 do
					-- Is the gap between this note and the next note greater than what's allowed?
					if((measureNotes[i+1] - measureNotes[i]) > noteGapThreshold) then
						isStream = false
					end
				end

				-- This measure is a stream
				if(isStream == true) then
					table.insert(streamMeasures, measureCount)
				end
			end

			-- Reset iterative variables
			measureTiming = 0
			measureCount = measureCount + 1
			measureNotes = {}
		else
			-- Iterate the measure timing
			measureTiming = measureTiming + 1

			-- Is this a note?
			if(line:match("["..TapNotesString.."]")) then
				table.insert(measureNotes, measureTiming)
			end
		end
	end

	return streamMeasures
end

-- Get the start/end of each stream sequence in our table of measures
local function getStreamSequences(streamMeasures, measureSequenceThreshold)
	local streamSequences = {}

	local counter = 1
	local streamEnd = nil
	-- Which sequences of measures are considered a stream?
	for k,v in pairs(streamMeasures) do
		-- Are we still in sequence?
		if(streamMeasures[k-1] == (streamMeasures[k] - 1)) then
			counter = counter + 1
			streamEnd = streamMeasures[k]
		end

		-- Are we out of sequence OR at the end of the array?
		if(streamMeasures[k+1] == nil or streamMeasures[k-1] ~= (streamMeasures[k] - 1)) then
			if(counter >= measureSequenceThreshold) then
				streamStart = (streamEnd - counter)
				table.insert(streamSequences, {streamStart=streamStart,streamEnd=streamEnd})
			end
			counter = 1
		end
	end

	return streamSequences
end


-- GetNoteDensity() accepts three arguments:
-- 		SongDir, a string representing the directory of the current song
-- 		StepsType, a string like "dance-single" or "pump-double"
-- 		Difficulty, a string like "Beginner" or "Challenge"

function GetNoteDensity(SongDir, StepsType, Difficulty)
	local SimfileString = GetSimfileString( SongDir )
	if not SimfileString then return end

	-- Discard header info; parse out only the notes
	local ChartString = GetSimfileChartString(SimfileString, StepsType, Difficulty)
	if not ChartString then return end

	-- Make our stream notes array into a string for regex
	local TapNotesString = ""
	for i, v in ipairs(TapNotes) do
		TapNotesString = TapNotesString .. v
	end

	-- the main density table, indexed by measure number
	local Density = {}
	-- Keep track of the measure
	local measureCount = 1
	-- Keep track of the number of notes in the current measure while we iterate
	local NotesInThisMeasure = 0
	local PeakNoteDensity = 0

	-- Loop through each line in our string of measures
	for line in ChartString:gmatch("[^\r\n]+") do

		-- If we hit a comma or a semi-colon, then we've hit the end of our measure
		if(line:match("^[,;]%s*")) then
			Density[measureCount] = NotesInThisMeasure
			if NotesInThisMeasure > PeakNoteDensity then PeakNoteDensity = NotesInThisMeasure end
			measureCount = measureCount + 1
			NotesInThisMeasure = 0
		else
			-- does this line contain a note?
			if(line:match("["..TapNotesString.."]")) then
				NotesInThisMeasure = NotesInThisMeasure + 1
			end
		end
	end

	return PeakNoteDensity, Density
end



function GetStreams(SongDir, StepsType, Difficulty, NotesPerMeasure, MeasureSequenceThreshold)

	local SimfileString = GetSimfileString( SongDir )
	if not SimfileString then return end

	-- Parse out just the contents of the notes
	local ChartString = GetSimfileChartString(SimfileString, StepsType, Difficulty)
	-- Which measures have enough notes to be considered as part of a stream?
	local StreamMeasures = getStreamMeasures(ChartString, NotesPerMeasure)

	-- Which sequences of measures are considered a stream?
	return (getStreamSequences(StreamMeasures, MeasureSequenceThreshold))
end