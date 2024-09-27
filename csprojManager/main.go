package main

import (
	"bufio"
	"encoding/json"
	"os"
	"regexp"
	"strings"
)

type Csproj interface {
	act(reader *bufio.Scanner, document *strings.Builder) bool
	setCsprojPath(csprojPath string)
	getCsprojPath()string
}
type Input_Add struct {
	CsprojPath     string
	WhenAddElement string
	ElementToAdd   string
}
// read the file line by line and add the text, if the text is not inserted return false
func (input Input_Add) act(reader *bufio.Scanner, document *strings.Builder) bool {
	whiteSpace := 0
	var line string
	var error = true
	for reader.Scan() {
		line = reader.Text()
		document.WriteString(line + "\n")
		if strings.Contains(line, input.ElementToAdd) {
			return false
		}
		if strings.Contains(line, input.WhenAddElement) {
			document.WriteString(strings.Repeat(" ", whiteSpace) + input.ElementToAdd + "\n")
			error = false
		}
		whiteSpace = strings.Index(line, "<")
	}
	return !error
}

func (input *Input_Add) getCsprojPath() string {
	return input.CsprojPath
}

func (input *Input_Add) setCsprojPath(csprojPath string) {
	input.CsprojPath = csprojPath
}

type Input_Remove struct {
	CsprojPath string
	ToRemove   string
}
// read the file line by line and remove the text
func (input Input_Remove) act(reader *bufio.Scanner, document *strings.Builder) bool {
	var line string
	var error = true
	for reader.Scan() {
		line = reader.Text()
		if !strings.Contains(line, input.ToRemove) {
			document.WriteString(line + "\n")
			error = false
		}
	}
	return !error
}

func (input *Input_Remove) getCsprojPath() string {
	return input.CsprojPath
}

func (input *Input_Remove) setCsprojPath(csprojPath string) {
	input.CsprojPath = csprojPath
}

func main() {
	In := os.Stdin
	Out := os.Stdout
	Err := os.Stderr

	var jsonInput []byte = make([]byte, 500)
	var mode []byte=make([]byte, 10)
	var error error
	var input Csproj=nil
	var bufReader *bufio.Reader = bufio.NewReader(In)
	mode, _ ,_= bufReader.ReadLine()
	bufReader.Read(jsonInput)
	jsonInput = []byte(strings.TrimRight(string(jsonInput), "\x00"))
	if string(mode) == "add" {
		input = &Input_Add{}
		error = json.Unmarshal(jsonInput, &input)
		input.setCsprojPath(string(input.(*Input_Add).CsprojPath))
	} else if string(mode) == "remove" {
		input = &Input_Remove{}
		error = json.Unmarshal(jsonInput, &input)
		input.setCsprojPath(string(input.(*Input_Remove).CsprojPath))
	}
	if error != nil {
		os.Stderr.WriteString("wrong input:" + string(jsonInput) + error.Error())
		return
	}
	if input == nil {
		os.Stderr.WriteString("wrong input:" + string(jsonInput))
		return
	}

	f, e := os.OpenFile(input.getCsprojPath(), os.O_RDWR, 0)
	if e != nil || f == nil {
		Err.WriteString("csproj not found")
		return
	}

	reader := bufio.NewScanner(f)
	reader.Scan()
	var document *strings.Builder = &strings.Builder{}
	document.WriteString(reader.Text() + "\n")
	if isSdk, _ := regexp.MatchString("Microsoft.NET.Sdk", reader.Text()); isSdk { //lettura intestazione
		Out.WriteString("found sdk csproj, no need to add element")
		return
	}
	defer f.Close()

	if input == nil {
		Err.WriteString("Error instantiate Csproj manager")
		return
	}
	if !input.act(reader, document) {
		Err.WriteString("Element no added")
		return
	}

	f.Seek(0, 0)
	f.Truncate(0)
	writer := bufio.NewWriter(f)
	_, e = writer.WriteString(document.String()[:len(document.String())-1])
	if e != nil {
		Err.WriteString(e.Error())
		return
	}
	writer.Flush()
	Err.WriteString("Element added")
}
