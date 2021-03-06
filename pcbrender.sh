#!/bin/sh

###########
# Written by ebastler/Moritz Plattner in 2021.
# Shell script to use the tracespace-cli application and inkscape in order to create PNG renders of a gerber folder.
# It will prompt for a soldermask color (default = black),  silkscreen color (default = white) and resolution (default = 300dpi, well suited for keyboard-sized PCBs)

colorListSM=("black" "white" "red" "blue" "purple" "green" "custom")
colorListRGBSM=("00,00,00" "255,255,255" "180,10,10" "00,00,128" "75,0,130" "0,66,0" "00,00,00")
colorAlphaSM=0.75

colorListSS=("white" "black" "custom")
colorListRGBSS=("255,255,255" "00,00,00" "255,255,255")

pngDPI=0

# Config: color codes for various parts of the output.
shColText='\033[0m'           # Color of the text written in prompts
shColVar='\033[0;37m'         # Color of brackets around the prompt numbers
shColNumbers='\033[38;5;45m'  # Color of the prompt numbers
shColDefault='\033[0m'        # Resets the output color to the terminal default

# Regex to match if input values are valid R,G,B where each color can range from 0 to 255
regexRGB="^(([0-1]?[0-9]?[0-9]?|2[0-4][0-9]|25[0-5]),){2}([0-1]?[0-9]?[0-9]?|2[0-4][0-9]|25[0-5]){1}$"

# This function asks the user to enter a valid RGB color code, and re-prompts until the input meets all conditions
RGBinput()
{
    read -p 'You selected using a custom color. Enter the desired RGB values (example for red: 128,0,0): ' inputColor
    until echo "$inputColor" | grep -qE "$regexRGB"
    do
        read -p 'Invalid color. Please use only 3 values between 0 and 255, separated by ",". Enter the desired RGB values (example for red: 128,0,0): ' inputColor
    done
    echo $inputColor
}

# This function prints a list of all entries of an array passed to it
OptionPrint()
{
    optionList=("$@")
    for (( i=0; i<${#optionList[@]}; i++))
    do
        printf '%b[%b%s%b]%b %s %b\n' $shColVar $shColNumbers $(($i+1)) $shColVar $shColText ${optionList[i]} $shColDefault
    done
    printf '\n'
}

# This function reads a user input (number) and checks if it is within the options of a given array
OptionChoice()
{
    optionList=("$@")
    read -p "Input: " colorChoice
    # Default to 1 if no choice is made
    colorChoice="${colorChoice:=1}"
    colorChoice=$(($colorChoice-1)) # Arrays begin at 0, the selector begins at 1 for easier use

    # Check if the color choice is within the list of options, otherwise default to 0
    if (( $colorChoice < 0 || $colorChoice > ${#optionList[@]}-1 ))
    then
        colorChoice=0
    fi
    echo $colorChoice
}

# Check if flags were passed to the script at launch, assign values.
# Set the "choice" variables to the value for "custom color" if given
while getopts m:s:d:v flag
do
    case "${flag}" in
        m) colorRGBSM=${OPTARG}
           colorChoiceSM=$((${#colorListSM[@]}-1));;
        s) colorRGBSS=${OPTARG}
           colorChoiceSS=$((${#colorListSS[@]}-1));;
        d) pngDPI=${OPTARG};;
        v) pngDPI=svg;;
    esac
done


# Only ask for soldermask colors if no valid RGB color was specified via flags
if ! echo "$colorRGBSM" | grep -qE "$regexRGB"
then
    # Print the list of available soldermask colors to the shell and poll for user input
    printf 'Choose a soldermask color (empty prompt = black). List of choices:\n'
    OptionPrint ${colorListSM[@]}
    colorChoiceSM=$(OptionChoice ${colorListSM[@]})

    # If the choice is the last element in the array (custom), ask for RGB values to assign to the array element
    # Perform a regex check to see if a valid RGB value has been used
    if (( $colorChoiceSM == ${#colorListSM[@]}-1))
    then
        colorListRGBSM[$colorChoiceSM]=$(RGBinput)
    fi
    colorRGBSM=${colorListRGBSM[$colorChoiceSM]}
fi

# Only ask for silkscreen colors if no valid RGB color was specified via flags
if ! echo "$colorRGBSS" | grep -qE "$regexRGB"
then
    # print the list of available silkscreen colors to the shell and poll for user input
    printf 'Choose a silkscreen color (empty prompt = white). List of choices:\n'
    OptionPrint ${colorListSS[@]}
    colorChoiceSS=$(OptionChoice ${colorListSS[@]})

    # If the choice is the last element in the array (custom), ask for RGB values to assign to the array element
    # Perform a regex check to see if a valid RGB value has been used
    if (( $colorChoiceSS == ${#colorListSS[@]}-1))
    then
        colorListRGBSS[$colorChoiceSS]=$(RGBinput)
    fi
    colorRGBSS=${colorListRGBSS[$colorChoiceSS]}
fi

# Only ask for dpi if no valid value was specified via flags, re-ask until a valid value is given
until (( $pngDPI > 0 && $pngDPI <= 10000 ))
do
    # Ask for DPI, unless the variable is set to "svg" in which case the loop is broken
    if [[ $pngDPI = svg ]]
    then
        break
    fi
    read -p "Choose the target DPI of the png. Default is 300, for small PCBs you should choose a higher value. 'svg' disables the conversion to png. " pngDPI
    # Default to 300 if not set
    pngDPI="${pngDPI:=300}"
done

printf '\nRendering images with soldermask color %s (R,G,B: %s, Alpha: %s) and silkscreen color %s (R,G,B: %s). DPI: %s \n' ${colorListSM[$colorChoiceSM]} $colorRGBSM $colorAlphaSM ${colorListSS[$colorChoiceSS]} $colorRGBSS $pngDPI

rm *.png
# Search for a file containing "Edge" and save it's name
outlineFilename=$(find . -maxdepth 1 -name "*Edge*" -printf '%f\n')
# Call tracespace cli with color and alpha from variables
# The -L parameter specifies that only the complete PCB should be rendered
# -g.optimizePaths=true will optimize file paths, not needed but adds little to compute time
# -l.${outlineFilename}.options.plotAsOutline=0.05 allows the tool to fix gaps up to 0.05mm in the edge cuts to avoid artifacts
tracespace -L -b.color.sm="rgba($colorRGBSM,$colorAlphaSM)" -b.color.ss="rgb($colorRGBSS)" -g.optimizePaths=true -l.${outlineFilename}.options.plotAsOutline=0.05 *

# Unless the user chose to save as avg, use find to get a list of all .svg, pass them as parameters to a subshell which calls inkscape
# The DPI are passed as the first parameter, filenames as second
if [[ $pngDPI != svg ]]
then
    find -name "*.svg" -exec sh -c 'tempVar=$1; inkscape $2 --export-dpi=$tempVar --export-filename=${2%.svg}.png' _ $pngDPI {} 1>/dev/null \; 
    rm *.svg
fi

exit 0
