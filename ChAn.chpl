use IO, List, Math, Map, Set, Path, FileSystem, Regex;

// Configuration parameters
config const inputDir: string = ".";
config const outputFile: string = "call_graph.pikchr";
config const maxDepth: int = 3;
config const includeBuiltins: bool = false;
config const analyzeComplexity: bool = true;
config const showParallelism: bool = true;
config const includeGPUKernels: bool = true;
config const complexityMetrics: bool = true;
config const distributedAnalysis: bool = true;

// Complexity metrics structure
record ComplexityMetrics {
    var cyclomaticComplexity: int = 1;
    var algorithmicComplexity: string = "O(1)";
    var parallelComplexity: string = "Sequential";
    var memoryComplexity: string = "O(1)";
    var distributedOps: int = 0;
    var gpuKernels: int = 0;
    var atomicOps: int = 0;
    var syncPoints: int = 0;
    var domainOps: int = 0;
    var localeAccess: int = 0;
    
    // Maintainability metrics
    var linesOfCode: int = 0;
    var commentLines: int = 0;
    var blankLines: int = 0;
    var halsteadVolume: real = 0.0;
    var halsteadDifficulty: real = 0.0;
    var maintainabilityIndex: real = 0.0;
    
    // Fan-in/Fan-out
    var fanIn: int = 0;
    var fanOut: int = 0;
    
    // Data locality metrics
    var sequentialAccess: int = 0;
    var randomAccess: int = 0;
    var cacheEfficiency: real = 0.0;
    var numaAwareness: int = 0;
    
    // Scalability metrics
    var parallelFraction: real = 0.0;
    var loadBalance: real = 1.0;
    var commCompRatio: real = 0.0;
    
    // GPU-specific metrics
    var coalescedAccess: int = 0;
    var threadDivergence: int = 0;
    var gpuOccupancy: real = 0.0;
}

// Function information structure
record FunctionInfo {
    var name: string;
    var moduleName: string;
    var filename: string;
    var lineNumber: int;
    var returnType: string;
    var parameters: list(string);
    var calledFunctions: set(string);
    var isBuiltin: bool = false;
    var complexity: ComplexityMetrics;
    var isParallel: bool = false;
    var isGPUKernel: bool = false;
    var isDistributed: bool = false;
    var domainRanks: list(int);
    var parallelConstructs: set(string);
}

// Type information structure
record TypeInfo {
    var name: string;
    var moduleName: string;
    var filename: string;
    var kind: string; // "record", "class", "enum", etc.
    var methods: set(string);
    var fields: list(string);
}

// Main analyzer class
class CallGraphAnalyzer {
    var functions: map(string, FunctionInfo);
    var types: map(string, TypeInfo);
    var callGraph: map(string, set(string));
    var visitedFiles: set(string);
    
    proc init() {
        this.functions = new map(string, FunctionInfo);
        this.types = new map(string, TypeInfo);
        this.callGraph = new map(string, set(string));
        this.visitedFiles = new set(string);
    }
    
    // Main project analysis method
    proc analyzeProject(projectPath: string) {
        writeln("Analyzing Chapel project in: ", projectPath);
        
        // Find all Chapel files
        var chapelFiles = findChapelFiles(projectPath);
        
        // Phase 1: Parse functions and types
        for fileItem in chapelFiles {
            if !this.visitedFiles.contains(fileItem) {
                this.parseFile(fileItem);
                this.visitedFiles.add(fileItem);
            }
        }
        
        // Phase 2: Analyze function calls
        for fileItem in chapelFiles {
            this.analyzeCalls(fileItem);
        }
        
        // Phase 3: Complexity analysis
        if analyzeComplexity {
            for fileItem in chapelFiles {
                this.analyzeComplexityProc(fileItem);
            }
        }
        
        // Phase 4: Calculate fan metrics
        this.calculateFanMetrics();
        
        writeln("Analysis completed:");
        writeln("- Functions found: ", this.functions.size);
        writeln("- Types found: ", this.types.size);
        writeln("- Call relationships: ", this.callGraph.size);
    }
    
    // Find Chapel files in directory
    proc findChapelFiles(dirPath: string): list(string) {
        var files = new list(string);
        
        try {
            for entry in listDir(dirPath) {
                if entry.endsWith(".chpl") {
                    files.pushBack(entry);
                }
            }
        } catch e {
            writeln("Error finding files: ", e.message());
        }
        
        return files;
    }
    
    // Parse a Chapel file
    proc parseFile(filename: string) {
        writeln("Parsing: ", filename);
        
        try {
            var fileHandle = open(filename, ioMode.r);
            var reader = fileHandle.reader();
            var lineNum = 0;
            var currentModuleName = extractModuleName(filename);
            
            for lineContent in reader.lines() {
                lineNum = lineNum + 1;
                var cleanLine = lineContent.strip();
                
                // Parse function definitions
                this.parseFunctionDefinition(cleanLine, filename, currentModuleName, lineNum);
                
                // Parse type definitions
                this.parseTypeDefinition(cleanLine, filename, currentModuleName, lineNum);
            }
            
            reader.close();
            fileHandle.close();
        } catch e {
            writeln("Error reading file ", filename, ": ", e.message());
        }
    }
    
    // Parse function definition using string methods
    proc parseFunctionDefinition(lineContent: string, filename: string, 
                                moduleName: string, lineNum: int) {
        // Simple pattern matching for "proc functionName("
        if lineContent.startsWith("proc ") {
            var procIndex = lineContent.find("proc ");
            if procIndex >= 0 {
                var afterProc = lineContent[procIndex + 5..];
                var parenIndex = afterProc.find("(");
                
                if parenIndex > 0 {
                    var funcName = afterProc[0..(parenIndex-1):int].strip();
                    
                    // Check for return type after )
                    var returnType = "void";
                    var colonIndex = lineContent.find("):");
                    if colonIndex >= 0 {
                        var afterColon = lineContent[colonIndex + 2..].strip();
                        var spaceIndex = afterColon.find(" ");
                        if spaceIndex >= 0 {
                            returnType = afterColon[0..(spaceIndex-1):int];
                        } else {
                            returnType = afterColon;
                        }
                    }
                    
                    var funcInfo = new FunctionInfo(
                        name = funcName,
                        moduleName = moduleName,
                        filename = filename,
                        lineNumber = lineNum,
                        returnType = returnType,
                        parameters = new list(string),
                        calledFunctions = new set(string),
                        complexity = new ComplexityMetrics(),
                        parallelConstructs = new set(string),
                        domainRanks = new list(int)
                    );
                    
                    // Parse parameters
                    this.parseParameters(lineContent, funcInfo.parameters);
                    
                    this.functions[funcName] = funcInfo;
                }
            }
        }
    }
    
    // Parse type definition using string methods
    proc parseTypeDefinition(lineContent: string, filename: string, 
                           moduleName: string, lineNum: int) {
        var typeKeywords = ["record ", "class ", "enum ", "union "];
        
        for keyword in typeKeywords {
            if lineContent.startsWith(keyword) {
                var afterKeyword = lineContent[keyword.size..];
                var spaceIndex = afterKeyword.find(" ");
                var braceIndex = afterKeyword.find("{");
                
                var endIndex = -1;
                if spaceIndex >= 0 && braceIndex >= 0 {
                    endIndex = min(spaceIndex:int, braceIndex:int);
                } else if spaceIndex >= 0 {
                    endIndex = spaceIndex:int;
                } else if braceIndex >= 0 {
                    endIndex = braceIndex:int;
                } else {
                    endIndex = afterKeyword.size;
                }
                
                if endIndex > 0 {
                    var typeName = afterKeyword[0..(endIndex-1):int].strip();
                    
                    var typeInfo = new TypeInfo(
                        name = typeName,
                        moduleName = moduleName,
                        filename = filename,
                        kind = keyword.strip(),
                        methods = new set(string),
                        fields = new list(string)
                    );
                    
                    this.types[typeName] = typeInfo;
                }
                break;
            }
        }
    }
    
    // Parse function parameters
    proc parseParameters(lineContent: string, ref params: list(string)) {
        var startIdx = lineContent.find("(");
        var endIdx = lineContent.find(")");
        
        if startIdx >= 0 && endIdx >= 0 && endIdx > startIdx {
            var paramStr = lineContent[startIdx+1..endIdx-1];
            if paramStr.strip() != "" {
                var parts = paramStr.split(",");
                for part in parts {
                    params.pushBack(part.strip());
                }
            }
        }
    }
    
    // Analyze function calls in a file
    proc analyzeCalls(filename: string) {
        try {
            var fileHandle = open(filename, ioMode.r);
            var reader = fileHandle.reader();
            var currentFunction = "";
            
            for lineContent in reader.lines() {
                var cleanLine = lineContent.strip();
                
                // Detect if we're inside a function
                if cleanLine.startsWith("proc ") {
                    var procIndex = cleanLine.find("proc ");
                    var afterProc = cleanLine[procIndex + 5..];
                    var parenIndex = afterProc.find("(");
                    
                    if parenIndex > 0 {
                        currentFunction = afterProc[0..(parenIndex-1):int].strip();
                    }
                }
                
                // Find function calls
                if currentFunction != "" {
                    this.findFunctionCalls(cleanLine, currentFunction);
                }
            }
            
            reader.close();
            fileHandle.close();
        } catch e {
            writeln("Error analyzing calls in ", filename, ": ", e.message());
        }
    }
    
    // Find function calls in a line
    proc findFunctionCalls(lineContent: string, caller: string) {
        // Simple approach: look for pattern "name("
        var i = 0;
        while i < lineContent.size {
            // Buscar en substring desde posición i
            var substring = lineContent[i..];
            var parenIndex = substring.find("(");
            if parenIndex < 0 then break;
            
            // Ajustar a posición absoluta en el string original
            var absoluteParenIndex = i + parenIndex;
            
            // Find start of function name
            var nameStart = absoluteParenIndex - 1;
            while nameStart >= 0 && (isAlphaNumeric(lineContent[nameStart]) || lineContent[nameStart] == '_') {
                nameStart = nameStart - 1;
            }
            nameStart = nameStart + 1;
            
            if nameStart < absoluteParenIndex {
                var calledFunc = lineContent[nameStart..absoluteParenIndex-1];
                
                // Check if it's a valid function call
                if calledFunc != caller && !isKeyword(calledFunc) && isValidIdentifier(calledFunc) {
                    if includeBuiltins || this.functions.contains(calledFunc) {
                        // Add to call graph
                        if !this.callGraph.contains(caller) {
                            this.callGraph[caller] = new set(string);
                        }
                        this.callGraph[caller].add(calledFunc);
                        
                        // Add to calling function
                        if this.functions.contains(caller) {
                            this.functions[caller].calledFunctions.add(calledFunc);
                        }
                    }
                }
            }
            
            i = absoluteParenIndex:int + 1;
        }
    }
    
    // Check if character is alphanumeric
    proc isAlphaNumeric(ch: string): bool {
        if ch.size != 1 then return false;

        try{
            var ascii_val = ch.toCodepoint();
            return (ascii_val >= 48 && ascii_val <= 57) ||  // 0-9
                (ascii_val >= 65 && ascii_val <= 90) ||  // A-Z
                (ascii_val >= 97 && ascii_val <= 122);   // a-z
        }
        catch{
            return false;
        }
    }
    
    // Check if string is valid identifier
    proc isValidIdentifier(str: string): bool {
        if str.size == 0 then return false;
        
        // Must start with letter or underscore
        var firstChar = str[0];
        if !(isAlphaNumeric(firstChar) || firstChar == "_") then return false;
        
        // Rest can be letters, numbers, or underscores
        for i in 1..str.size-1 {
            var ch = str[i];
            if !(isAlphaNumeric(ch) || ch == "_") then return false;
        }
        
        return true;
    }
    
    // Analyze complexity for a file
    proc analyzeComplexityProc(filename: string) {
        try {
            var fileHandle = open(filename, ioMode.r);
            var reader = fileHandle.reader();
            var currentFunction = "";
            var functionBody: list(string);
            var insideFunction = false;
            var braceCount = 0;
            
            for lineContent in reader.lines() {
                var cleanLine = lineContent.strip();
                
                // Detect function start
                if cleanLine.startsWith("proc ") {
                    // Process previous function if exists
                    if currentFunction != "" && insideFunction {
                        this.computeFunctionComplexity(currentFunction, functionBody);
                    }
                    
                    var procIndex = cleanLine.find("proc ");
                    var afterProc = cleanLine[procIndex + 5..];
                    var parenIndex = afterProc.find("(");
                    
                    if parenIndex > 0 {
                        currentFunction = afterProc[0..(parenIndex-1):int].strip();
                        functionBody.clear();
                        insideFunction = true;
                        braceCount = 0;
                    }
                }
                
                if insideFunction {
                    functionBody.pushBack(cleanLine);
                    
                    // Count braces to detect function end
                    for ch in cleanLine {
                        if ch == "{" then braceCount = braceCount + 1;
                        if ch == "}" then braceCount = braceCount - 1;
                    }
                    
                    if braceCount <= 0 && cleanLine.endsWith("}") {
                        this.computeFunctionComplexity(currentFunction, functionBody);
                        insideFunction = false;
                        currentFunction = "";
                    }
                }
            }
            
            // Process last function if pending
            if currentFunction != "" && insideFunction {
                this.computeFunctionComplexity(currentFunction, functionBody);
            }
            
            reader.close();
            fileHandle.close();
        } catch e {
            writeln("Error in complexity analysis for ", filename, ": ", e.message());
        }
    }
    
    // Compute complexity metrics for a function
    proc computeFunctionComplexity(funcName: string, functionBody: list(string)) {
        if !this.functions.contains(funcName) {
            return;
        }
        
        ref funcInfo = this.functions[funcName];
        ref metrics = funcInfo.complexity;
        
        // Join all lines into single text
        var bodyText = "";
        for lineItem in functionBody {
            bodyText = bodyText + lineItem + "\n";
        }
        
        // Calculate cyclomatic complexity
        metrics.cyclomaticComplexity = this.calculateCyclomaticComplexity(bodyText);
        
        // Analyze algorithmic complexity
        metrics.algorithmicComplexity = this.estimateAlgorithmicComplexity(bodyText);
        
        // Analyze memory complexity
        metrics.memoryComplexity = this.estimateMemoryComplexity(bodyText);
        
        // Analyze parallelism
        this.analyzeParallelism(bodyText, funcInfo);
        
        // Analyze distributed operations
        this.analyzeDistributedOperations(bodyText, funcInfo);
        
        // Analyze GPU kernels
        this.analyzeGPUKernels(bodyText, funcInfo);
        
        // Count special operations
        metrics.atomicOps = this.countAtomicOperations(bodyText);
        metrics.syncPoints = this.countSynchronizationPoints(bodyText);
        metrics.domainOps = this.countDomainOperations(bodyText);
        metrics.localeAccess = this.countLocaleAccess(bodyText);
        
        // Calculate maintainability metrics
        this.calculateMaintainabilityMetrics(bodyText, funcInfo);
        
        // Calculate data locality metrics
        this.calculateDataLocalityMetrics(bodyText, funcInfo);
        
        // Calculate scalability metrics
        this.calculateScalabilityMetrics(bodyText, funcInfo);
        
        // Calculate GPU metrics if applicable
        if funcInfo.isGPUKernel {
            this.calculateGPUMetrics(bodyText, funcInfo);
        }
    }
    
    // Calculate cyclomatic complexity
    proc calculateCyclomaticComplexity(code: string): int {
        var complexity = 1; // Base path
        
        // Count decision points
        complexity = complexity + countOccurrences(code, "if ");
        complexity = complexity + countOccurrences(code, "else");
        complexity = complexity + countOccurrences(code, "while ");
        complexity = complexity + countOccurrences(code, "for ");
        complexity = complexity + countOccurrences(code, "do ");
        complexity = complexity + countOccurrences(code, "select ");
        complexity = complexity + countOccurrences(code, "when ");
        complexity = complexity + countOccurrences(code, "&&");
        complexity = complexity + countOccurrences(code, "||");
        complexity = complexity + countOccurrences(code, "otherwise");
        
        return complexity;
    }
    
    proc countOccurrences(text: string, pattern: string): int {
        var count = 0;
        var pos = 0;
        
        while pos < text.size {
            var substring = text[pos..];
            var found = substring.find(pattern);
            
            if found < 0 then break;
            
            count = count + 1;
            pos = pos + found:int + pattern.size;
        }
        
        return count;
    }
    
    // Estimate algorithmic complexity
    proc estimateAlgorithmicComplexity(code: string): string {
        var maxNesting = analyzeLoopNesting(code);
        var hasRecursion = detectRecursion(code);
        var hasDomainIteration = code.find("forall")>0 || code.find("coforall")>0;
        var hasMatrixOps = code.find("dot")>0 || (code.find("*")>0 && code.find("[")>0);
        
        if hasRecursion {
            if code.find("memo")>0 || code.find("cache")>0 {
                return "O(n)";
            } else {
                return "O(2^n)";
            }
        } else if maxNesting >= 3 {
            return "O(n^" + maxNesting:string + ")";
        } else if maxNesting == 2 {
            if hasMatrixOps {
                return "O(n^3)";
            } else {
                return "O(n^2)";
            }
        } else if maxNesting == 1 {
            if hasDomainIteration {
                return "O(n*p)";
            } else {
                return "O(n)";
            }
        } else {
            return "O(1)";
        }
    }
    
    // Analyze loop nesting depth
    proc analyzeLoopNesting(code: string): int {
        var lines = code.split("\n");
        var currentNesting = 0;
        var maxNesting = 0;
        
        for lineItem in lines {
            var trimmed = lineItem.strip();
            
            // Check for loop starts
            if trimmed.startsWith("for ") || trimmed.startsWith("while ") || 
               trimmed.startsWith("do ") || trimmed.startsWith("forall ") ||
               trimmed.startsWith("coforall ") {
                currentNesting = currentNesting + 1;
                if currentNesting > maxNesting {
                    maxNesting = currentNesting;
                }
            }
            
            // Check for block end
            if trimmed.find("}")>0 {
                if currentNesting > 0 {
                    currentNesting = currentNesting - 1;
                }
            }
        }
        
        return maxNesting;
    }
    
    // Detect recursion in code
    proc detectRecursion(code: string): bool {
        return code.find("return")>0 && code.find("(")>0;
    }
    
    // Estimate memory complexity
    proc estimateMemoryComplexity(code: string): string {
        var arrayAllocations = countOccurrences(code, "new ") + countOccurrences(code, "allocate");
        var domainCreations = countOccurrences(code, "{") + countOccurrences(code, "..");
        var hasRecursion = detectRecursion(code);
        
        if hasRecursion {
            return "O(n)";
        } else if arrayAllocations > 0 || domainCreations > 0 {
            return "O(n)";
        } else {
            return "O(1)";
        }
    }
    
    // Analyze parallelism patterns
    proc analyzeParallelism(code: string, ref funcInfo: FunctionInfo) {
        var parallelKeywords = ["forall", "coforall", "begin", "cobegin", "sync", "single"];
        
        for keyword in parallelKeywords {
            if code.find(keyword)>0 {
                funcInfo.parallelConstructs.add(keyword);
                funcInfo.isParallel = true;
                
                select keyword {
                    when "forall" {
                        funcInfo.complexity.parallelComplexity = "Data Parallel";
                    }
                    when "coforall" {
                        funcInfo.complexity.parallelComplexity = "Task Parallel";
                    }
                    when "begin" {
                        funcInfo.complexity.parallelComplexity = "Async Task";
                    }
                    when "cobegin" {
                        funcInfo.complexity.parallelComplexity = "Structured Parallel";
                    }
                    when "sync" do funcInfo.complexity.parallelComplexity = "Synchronized";
                    when "single" do funcInfo.complexity.parallelComplexity = "Synchronized";
                }
            }
        }
    }
    
    // Analyze distributed operations
    proc analyzeDistributedOperations(code: string, ref funcInfo: FunctionInfo) {
        var distKeywords = ["on ", "Locales", "here", "numLocales"];
        var foundDist = false;
        
        for keyword in distKeywords {
            if code.find(keyword)>0 {
                foundDist = true;
                funcInfo.complexity.distributedOps = funcInfo.complexity.distributedOps + countOccurrences(code, keyword);
            }
        }
        
        if foundDist {
            funcInfo.isDistributed = true;
            
            if code.find("on Locales")>0 {
                funcInfo.complexity.parallelComplexity = "SPMD Distributed";
            } else if code.find("on here")>0 {
                funcInfo.complexity.parallelComplexity = "Local Distributed";
            } else {
                funcInfo.complexity.parallelComplexity = "Remote Distributed";
            }
        }
    }
    
    // Analyze GPU kernels
    proc analyzeGPUKernels(code: string, ref funcInfo: FunctionInfo) {
        var gpuKeywords = ["@gpu", "@assertOnGpu", "@blockSize", "@cuda"];
        var foundGPU = false;
        
        for keyword in gpuKeywords {
            if code.find(keyword)>0 {
                foundGPU = true;
                funcInfo.complexity.gpuKernels = funcInfo.complexity.gpuKernels + 1;
            }
        }
        
        if foundGPU {
            funcInfo.isGPUKernel = true;
            funcInfo.complexity.parallelComplexity = "GPU Parallel";
            
            if code.find("@blockSize")>0 {
                funcInfo.complexity.parallelComplexity = "GPU Block Parallel";
            }
            if code.find("@cuda")>0 {
                funcInfo.complexity.parallelComplexity = "CUDA Kernel";
            }
        }
    }
    
    // Count atomic operations
    proc countAtomicOperations(code: string): int {
        var atomicKeywords = ["atomic", "fence"];
        var count = 0;
        
        for keyword in atomicKeywords {
            count = count + countOccurrences(code, keyword);
        }
        
        return count;
    }
    
    // Count synchronization points
    proc countSynchronizationPoints(code: string): int {
        var syncKeywords = ["sync", "barrier", "waitfor", "join"];
        var count = 0;
        
        for keyword in syncKeywords {
            count = count + countOccurrences(code, keyword);
        }
        
        return count;
    }
    
    // Count domain operations
    proc countDomainOperations(code: string): int {
        var domainKeywords = ["forall", "reduce", "scan"];
        var count = 0;
        
        for keyword in domainKeywords {
            count = count + countOccurrences(code, keyword);
        }
        
        count = count + countOccurrences(code, "..");
        return count;
    }
    
    // Count locale access operations
    proc countLocaleAccess(code: string): int {
        var localeKeywords = ["on ", "Locales", "here."];
        var count = 0;
        
        for keyword in localeKeywords {
            count = count + countOccurrences(code, keyword);
        }
        
        return count;
    }
    
    // Calculate maintainability metrics
    proc calculateMaintainabilityMetrics(code: string, ref funcInfo: FunctionInfo) {
        ref metrics = funcInfo.complexity;
        var lines = code.split("\n");
        
        // Count line types
        for lineItem in lines {
            var trimmed = lineItem.strip();
            if trimmed == "" {
                metrics.blankLines = metrics.blankLines + 1;
            } else if trimmed.startsWith("//") || trimmed.find("/*")>0 {
                metrics.commentLines = metrics.commentLines + 1;
            } else {
                metrics.linesOfCode = metrics.linesOfCode + 1;
            }
        }
        
        // Calculate Halstead metrics (simplified)
        var operatorCount = countOccurrences(code, "+") + countOccurrences(code, "-") + 
                           countOccurrences(code, "*") + countOccurrences(code, "/") +
                           countOccurrences(code, "=") + countOccurrences(code, "<") +
                           countOccurrences(code, ">") + countOccurrences(code, "!");
        
        var operandCount = countIdentifiers(code);
        
        if operatorCount > 0 && operandCount > 0 {
            var vocabulary = 10.0 + operandCount:real; // Simplified
            var length = operatorCount:real + operandCount:real;
            
            metrics.halsteadVolume = length * log2(vocabulary);
            metrics.halsteadDifficulty = 5.0 * (operandCount:real / 10.0);
            
            // Maintainability Index
            var avgCC = metrics.cyclomaticComplexity:real;
            var avgLOC = metrics.linesOfCode:real;
            
            if avgLOC > 0 {
                metrics.maintainabilityIndex = max(0.0, 
                    171.0 - 5.2 * log(metrics.halsteadVolume) - 
                    0.23 * avgCC - 16.2 * log(avgLOC));
            }
        }
    }
    
    // Count identifiers in code (simplified)
    proc countIdentifiers(code: string): int {
        var count = 0;
        var i = 0;
        
        while i < code.size {
            if isAlphaNumeric(code[i]) || code[i] == "_" {
                // Start of identifier
                var start = i;
                while i < code.size && (isAlphaNumeric(code[i]) || code[i] == "_") {
                    i = i + 1;
                }
                
                var identifier = code[start..i-1];
                if isValidIdentifier(identifier) && !isKeyword(identifier) {
                    count = count + 1;
                }
            } else {
                i = i + 1;
            }
        }
        
        return count;
    }
    
    // Calculate data locality metrics
    proc calculateDataLocalityMetrics(code: string, ref funcInfo: FunctionInfo) {
        ref metrics = funcInfo.complexity;
        
        // Count array access patterns
        var arrayAccesses = countOccurrences(code, "[") + countOccurrences(code, "]");
        var stridedAccesses = countOccurrences(code, "::");
        
        metrics.sequentialAccess = arrayAccesses - stridedAccesses;
        metrics.randomAccess = stridedAccesses;
        
        // Estimate cache efficiency
        if arrayAccesses > 0 {
            metrics.cacheEfficiency = metrics.sequentialAccess:real / arrayAccesses:real;
        }
        
        // Analyze NUMA awareness
        var numaKeywords = ["here", "Locales", "on "];
        for keyword in numaKeywords {
            metrics.numaAwareness = metrics.numaAwareness + countOccurrences(code, keyword);
        }
    }
    
    // Calculate scalability metrics
    proc calculateScalabilityMetrics(code: string, ref funcInfo: FunctionInfo) {
        ref metrics = funcInfo.complexity;
        
        // Estimate parallelizable fraction
        var totalOps = countOccurrences(code, ";");
        var parallelOps = 0;
        
        if code.find("forall")>0 || code.find("coforall")>0 {
            parallelOps = (totalOps * 0.7):int; // Estimate 70% parallel
        }
        
        if totalOps > 0 {
            metrics.parallelFraction = parallelOps:real / totalOps:real;
        }
        
        // Estimate load balance
        if funcInfo.isDistributed {
            if code.find("cyclic")>0 {
                metrics.loadBalance = 0.9;
            } else if code.find("block")>0 {
                metrics.loadBalance = 0.8;
            } else {
                metrics.loadBalance = 0.6;
            }
        }
        
        // Calculate communication/computation ratio
        var commOps = metrics.localeAccess + metrics.syncPoints;
        var compOps = totalOps - commOps;
        
        if compOps > 0 {
            metrics.commCompRatio = commOps:real / compOps:real;
        }
    }
    
    // Calculate GPU-specific metrics
    proc calculateGPUMetrics(code: string, ref funcInfo: FunctionInfo) {
        ref metrics = funcInfo.complexity;
        
        // Count coalesced accesses
        var coalescedKeywords = ["@blockIdx", "@threadIdx", "@blockDim"];
        for keyword in coalescedKeywords {
            metrics.coalescedAccess = metrics.coalescedAccess + countOccurrences(code, keyword);
        }
        
        // Count thread divergence points
        if code.find("if")>0 && (code.find("@threadIdx")>0 || code.find("@blockIdx")>0) {
            metrics.threadDivergence = countOccurrences(code, "if");
        }
        
        // Estimate GPU occupancy
        var registersUsed = countOccurrences(code, "var") + countOccurrences(code, "const");
        
        if registersUsed > 0 {
            metrics.gpuOccupancy = min(1.0, 1.0 / (registersUsed:real * 0.1));
        } else {
            metrics.gpuOccupancy = 1.0;
        }
    }
    
    // Calculate fan-in/fan-out metrics
    proc calculateFanMetrics() {
        // Initialize fan-in for all functions
        for funcName in this.functions.keys() {
            this.functions[funcName].complexity.fanIn = 0;
        }
        
        // Calculate fan-out and fan-in
        for caller in this.callGraph.keys() {
            var callees = this.callGraph[caller];
            if this.functions.contains(caller) {
                // Fan-out: number of functions this function calls
                this.functions[caller].complexity.fanOut = callees.size;
                
                // Fan-in: increment counter for each called function
                for callee in callees {
                    if this.functions.contains(callee) {
                        this.functions[callee].complexity.fanIn = this.functions[callee].complexity.fanIn + 1;
                    }
                }
            }
        }
    }
    
    // Helper function for log base 2
    proc log2(x: real): real {
        return log(x) / log(2.0);
    }
    
    // Check if word is Chapel keyword
    proc isKeyword(word: string): bool {
        var keywords = ["if", "else", "while", "for", "do", "begin", "end", 
                       "var", "const", "param", "type", "return", "yield",
                       "writeln", "write", "use", "import", "proc", "class",
                       "record", "enum", "union", "select", "when", "otherwise"];
        
        for keyword in keywords {
            if word == keyword {
                return true;
            }
        }
        return false;
    }
    
    // Extract moduleName name from filename
    proc extractModuleName(filename: string): string {
        var baseName = basename(filename);
        var dotIdx = baseName.rfind(".");
        if dotIdx >= 0 {
            return baseName[0..(dotIdx-1):int];
        }
        return baseName;
    }

    proc generatePikChrDiagram(): string {
        var pikchr = "/* Chapel Call Graph with Complexity Metrics */\n\n";
        
        // Configuración optimizada para visibilidad
        //pikchr += "boxwid = 1.8\n";
        //pikchr += "boxht = 0.8\n";
        //pikchr += "arrowwid = 0.1\n";
        //pikchr += "arrowht = 0.15\n\n";
        
        var functionToBoxName: map(string, string);
        var nodesPerRow = 4;  // Más columnas para mejor distribución
        
        // Recopilar funciones
        var funcList: list(string);
        for funcName in this.functions.keys() {
            if shouldIncludeFunction(funcName) {
                funcList.pushBack(funcName);
            }
        }
        
        // Generar boxes con espaciado optimizado
        for i in 0..funcList.size-1 {
            var funcName = funcList[i];
            var boxName = "Box" + i:string;
            functionToBoxName[funcName] = boxName;
            
            ref funcInfo = this.functions[funcName];
            
            // Determinar color
            var fillColor = "lightgray";
            if funcInfo.isGPUKernel {
                fillColor = "yellow";
            } else if funcInfo.isDistributed {
                fillColor = "lightblue";
            } else if funcInfo.isParallel {
                fillColor = "lightgreen";
            }
            
            // Posicionamiento en grid regular
            if i == 0 {
                pikchr += boxName + ": box fill " + fillColor + " \"" + funcName + "\"\n";
            } else {
                var row = i / nodesPerRow;
                var col = i % nodesPerRow;
                
                if col == 0 {
                    // Primera columna de nueva fila
                    pikchr += boxName + ": box fill " + fillColor + " \"" + funcName + "\" " +
                            "at Box0 + (0, " + (-row * 2.5):string + "cm)\n";
                } else {
                    // Misma fila, siguiente columna
                    var refBox = "Box" + (row * nodesPerRow):string;
                    pikchr += boxName + ": box fill " + fillColor + " \"" + funcName + "\" " +
                            "at " + refBox + " + (" + (col * 2.5):string + "cm, 0)\n";
                }
            }
            
            // Métricas más compactas
            if complexityMetrics {
                pikchr += "text \"CC:" + funcInfo.complexity.cyclomaticComplexity:string + "\" " +
                        "at " + boxName + ".s + (0,-0.25)\n";
                pikchr += "text \"" + funcInfo.complexity.algorithmicComplexity + "\" " +
                        "at " + boxName + ".s + (0,-0.45)\n";
            }
        }
        
        // Conexiones con flechas más visibles
        pikchr += "\n/* Connections */\n";
        var connectionCount = 0;
        var maxConnections = 20; // Limitar para evitar sobrecarga visual
        
        for caller in this.callGraph.keys() {
            if functionToBoxName.contains(caller) && connectionCount < maxConnections {
                var callees = this.callGraph[caller];
                for callee in callees {
                    if functionToBoxName.contains(callee) && connectionCount < maxConnections {
                        var callerBox = functionToBoxName[caller];
                        var calleeBox = functionToBoxName[callee];
                        
                        var arrowStyle = "arrow";
                        if this.functions.contains(callee) {
                            ref calleeInfo = this.functions[callee];
                            if calleeInfo.isGPUKernel {
                                arrowStyle = "arrow thick color red";
                            } else if calleeInfo.isDistributed {
                                arrowStyle = "arrow thick color blue";
                            } else if calleeInfo.isParallel {
                                arrowStyle = "arrow thick color green";
                            }
                        }
                        
                        pikchr += arrowStyle + " from " + callerBox + ".e to " + calleeBox + ".w\n";
                        connectionCount += 1;
                    }
                }
            }
        }
        
        // Leyenda compacta
        if complexityMetrics && funcList.size > 0 {
            var totalRows = (funcList.size + nodesPerRow - 1) / nodesPerRow;
            pikchr += "\n/* Legend */\n";
            pikchr += "Legend: box \"Legend\" width 1.5 height 0.5 " +
                    "at Box0 + (-2cm, " + (-(totalRows + 1) * 2.5):string + "cm)\n";
            pikchr += "text \"CC=Cyclomatic\" at Legend.s + (0,-0.3)\n";
            pikchr += "text \"Gray=Seq Blue=Dist Green=Par Yellow=GPU\" " +
                    "at Legend.s + (0,-0.6) \n";
        }
        
        return pikchr;
    }

    // Determine arrow style based on call type
    proc getArrowStyle(caller: string, callee: string): string {
        if !this.functions.contains(caller) || !this.functions.contains(callee) {
            return "arrow";
        }
        
        ref callerInfo = this.functions[caller];
        ref calleeInfo = this.functions[callee];
        
        // GPU kernel call
        if calleeInfo.isGPUKernel {
            return "arrow thick color gold";
        }
        
        // Distributed call
        if callerInfo.isDistributed || calleeInfo.isDistributed {
            return "arrow thick color blue";
        }
        
        // Parallel call
        if callerInfo.isParallel || calleeInfo.isParallel {
            return "arrow thick color green";
        }
        
        // Sequential call
        return "arrow";
    }
    
    // Check if function should be included in diagram
    proc shouldIncludeFunction(funcName: string): bool {
        if !includeBuiltins && !this.functions.contains(funcName) {
            return false;
        }
        
        // Filter system functions if builtins not included
        if !includeBuiltins {
            var systemFuncs = ["writeln", "write", "halt", "exit"];
            for sysFunc in systemFuncs {
                if funcName == sysFunc {
                    return false;
                }
            }
        }
        
        return true;
    }
    
    // Calculate call depth
    proc calculateCallDepth(fromFunc: string, toFunc: string): int {
        // Simple implementation - return depth 1
        return 1;
    }
    
    // Save diagram to file
    proc saveDiagram(diagram: string, filename: string) {
        try {
            var fileHandle = open(filename, ioMode.cw);
            var writer = fileHandle.writer();
            writer.write(diagram);
            writer.close();
            fileHandle.close();
            writeln("Diagram saved to: ", filename);
        } catch e {
            writeln("Error saving diagram: ", e.message());
        }
    }
    
    // Print analysis statistics
    proc printStatistics() {
        writeln("\n=== Analysis Statistics ===");
        writeln("Functions analyzed: ", this.functions.size);
        writeln("Data types found: ", this.types.size);
        writeln("Call relationships: ", this.callGraph.size);
        writeln("Maximum depth: ", maxDepth);
        writeln("Include builtins: ", includeBuiltins);
        
        if analyzeComplexity {
            writeln("\n=== Complexity Metrics ===");
            var totalComplexity = 0;
            var parallelFunctions = 0;
            var gpuFunctions = 0;
            var distributedFunctions = 0;
            var maxCyclomaticComplexity = 0;
            var complexityDistribution: map(string, int);
            
            for funcName in this.functions.keys() {
                ref funcInfo = this.functions[funcName];
                totalComplexity = totalComplexity + funcInfo.complexity.cyclomaticComplexity;
                if funcInfo.complexity.cyclomaticComplexity > maxCyclomaticComplexity {
                    maxCyclomaticComplexity = funcInfo.complexity.cyclomaticComplexity;
                }
                
                if funcInfo.isParallel then parallelFunctions = parallelFunctions + 1;
                if funcInfo.isGPUKernel then gpuFunctions = gpuFunctions + 1;
                if funcInfo.isDistributed then distributedFunctions = distributedFunctions + 1;
                
                // Classify by algorithmic complexity
                var algComplexity = funcInfo.complexity.algorithmicComplexity;
                if complexityDistribution.contains(algComplexity) {
                    complexityDistribution[algComplexity] = complexityDistribution[algComplexity] + 1;
                } else {
                    complexityDistribution[algComplexity] = 1;
                }
            }
            
            var avgComplexity = if this.functions.size > 0 then 
                               totalComplexity:real / this.functions.size:real else 0.0;
            
            writeln("Average cyclomatic complexity: ", avgComplexity:string);
            writeln("Maximum cyclomatic complexity: ", maxCyclomaticComplexity);
            writeln("Parallel functions: ", parallelFunctions, " (", 
                   (parallelFunctions:real / this.functions.size:real * 100):int, "%)");
            writeln("GPU kernels: ", gpuFunctions);
            writeln("Distributed functions: ", distributedFunctions);
            
            // Maintainability metrics
            var totalLOC = 0;
            var totalMI = 0.0;
            var avgFanIn = 0.0;
            var avgFanOut = 0.0;
            
            for funcName in this.functions.keys() {
                ref funcInfo = this.functions[funcName];
                totalLOC = totalLOC + funcInfo.complexity.linesOfCode;
                totalMI = totalMI + funcInfo.complexity.maintainabilityIndex;
                avgFanIn = avgFanIn + funcInfo.complexity.fanIn:real;
                avgFanOut = avgFanOut + funcInfo.complexity.fanOut:real;
            }
            
            var avgMI = totalMI / this.functions.size:real;
            avgFanIn = avgFanIn / this.functions.size:real;
            avgFanOut = avgFanOut / this.functions.size:real;
            
            writeln("\n=== Maintainability Metrics ===");
            writeln("Total lines of code: ", totalLOC);
            writeln("Average maintainability index: ", avgMI:int);
            writeln("Average fan-in: ", avgFanIn:string);
            writeln("Average fan-out: ", avgFanOut:string);
            
            writeln("\n=== Algorithmic Complexity Distribution ===");
            for complexity in complexityDistribution.keys() {
                var count = complexityDistribution[complexity];
                writeln(complexity, ": ", count, " functions");
            }
            
            // Scalability metrics
            writeln("\n=== Scalability Analysis ===");
            var avgParallelFraction = 0.0;
            var avgCommCompRatio = 0.0;
            var functionsWithGoodScalability = 0;
            
             for funcName in this.functions.keys() {
                ref funcInfo = this.functions[funcName];
                avgParallelFraction = avgParallelFraction + funcInfo.complexity.parallelFraction;
                avgCommCompRatio = avgCommCompRatio + funcInfo.complexity.commCompRatio;
                
                if funcInfo.complexity.parallelFraction > 0.7 && 
                   funcInfo.complexity.commCompRatio < 0.3 {
                    functionsWithGoodScalability = functionsWithGoodScalability + 1;
                }
            }
            
            avgParallelFraction = avgParallelFraction / this.functions.size:real;
            avgCommCompRatio = avgCommCompRatio / this.functions.size:real;
            
            writeln("Average parallelizable fraction: ", (avgParallelFraction * 100):int, "%");
            writeln("Communication/computation ratio: ", (avgCommCompRatio * 100):int, "%");
            writeln("Functions with good scalability: ", functionsWithGoodScalability, 
                   " (", (functionsWithGoodScalability:real / this.functions.size:real * 100):int, "%)");
        }
        
        if showParallelism {
            writeln("\n=== Parallelism Analysis ===");
            this.printParallelismStatistics();
        }
        
        writeln("\n=== Top 5 Functions by Calls ===");
        var functionCounts: list((string, int));
        
        for funcName in this.callGraph.keys() {
            var callees = this.callGraph[funcName];
            functionCounts.pushBack((funcName, callees.size));
        }
        
        // Simple sorting by call count
        for i in 0..min(4, functionCounts.size-1) {
            var (name, count) = functionCounts[i];
            if this.functions.contains(name) {
                ref funcInfo = this.functions[name];
                write(i+1, ". ", name, " -> ", count, " calls");
                if complexityMetrics {
                    write(" [CC:", funcInfo.complexity.cyclomaticComplexity, 
                         ", ", funcInfo.complexity.algorithmicComplexity, "]");
                }
                writeln();
            }
        }
        
        if complexityMetrics {
            writeln("\n=== High Complexity Functions ===");
            this.printHighComplexityFunctions();
        }
    }
    
    // Print parallelism statistics
    proc printParallelismStatistics() {
        var parallelConstructCounts: map(string, int);
        var totalAtomicOps = 0;
        var totalSyncPoints = 0;
        var maxDomainRank = 0;
        
        for funcName in this.functions.keys() {
            ref funcInfo = this.functions[funcName];
            for construct in funcInfo.parallelConstructs {
                if parallelConstructCounts.contains(construct) {
                    parallelConstructCounts[construct] = parallelConstructCounts[construct] + 1;
                } else {
                    parallelConstructCounts[construct] = 1;
                }
            }
            
            totalAtomicOps = totalAtomicOps + funcInfo.complexity.atomicOps;
            totalSyncPoints = totalSyncPoints + funcInfo.complexity.syncPoints;
            
            for rankValue in funcInfo.domainRanks {
                if rankValue > maxDomainRank {
                    maxDomainRank = rankValue;
                }
            }
        }
        
        writeln("Parallel constructs found:");
        for construct in parallelConstructCounts.keys() {
            var count = parallelConstructCounts[construct];
            writeln("  ", construct, ": ", count, " uses");
        }
        
        writeln("Total atomic operations: ", totalAtomicOps);
        writeln("Total synchronization points: ", totalSyncPoints);
        writeln("Maximum domain dimension: ", maxDomainRank);
        
        // Data locality statistics
        var totalSequentialAccess = 0;
        var totalRandomAccess = 0;
        var avgCacheEfficiency = 0.0;
        var functionsWithGoodLocality = 0;
        
        for funcName in this.functions.keys() {
            ref funcInfo = this.functions[funcName];
            totalSequentialAccess = totalSequentialAccess + funcInfo.complexity.sequentialAccess;
            totalRandomAccess = totalRandomAccess + funcInfo.complexity.randomAccess;
            avgCacheEfficiency = avgCacheEfficiency + funcInfo.complexity.cacheEfficiency;
            
            if funcInfo.complexity.cacheEfficiency > 0.7 {
                functionsWithGoodLocality = functionsWithGoodLocality + 1;
            }
        }
        
        avgCacheEfficiency = avgCacheEfficiency / this.functions.size:real;
        
        writeln("\n=== Data Locality Analysis ===");
        writeln("Sequential accesses: ", totalSequentialAccess);
        writeln("Random accesses: ", totalRandomAccess);
        writeln("Average cache efficiency: ", (avgCacheEfficiency * 100):int, "%");
        writeln("Functions with good locality: ", functionsWithGoodLocality);
    }
    
    // Print high complexity functions
    proc printHighComplexityFunctions() {
        var highComplexityThreshold = 10;
        var found = false;
        
        for funcName in this.functions.keys() {
            ref funcInfo = this.functions[funcName];
            if funcInfo.complexity.cyclomaticComplexity >= highComplexityThreshold {
                if !found {
                    writeln("Functions with cyclomatic complexity >= ", highComplexityThreshold, ":");
                    found = true;
                }
                
                writeln("  ", funcName, ": CC=", funcInfo.complexity.cyclomaticComplexity,
                       ", Alg=", funcInfo.complexity.algorithmicComplexity,
                       ", Mem=", funcInfo.complexity.memoryComplexity,
                       ", MI=", funcInfo.complexity.maintainabilityIndex:int);
                
                writeln("    Fan-in: ", funcInfo.complexity.fanIn, 
                       ", Fan-out: ", funcInfo.complexity.fanOut,
                       ", LOC: ", funcInfo.complexity.linesOfCode);
                
                if funcInfo.isParallel {
                    write("    Parallelism: ", funcInfo.complexity.parallelComplexity);
                    if !funcInfo.parallelConstructs.isEmpty() {
                        write(" (");
                        var first = true;
                        for construct in funcInfo.parallelConstructs {
                            if !first then write(", ");
                            write(construct);
                            first = false;
                        }
                        write(")");
                    }
                    writeln();
                    writeln("    Parallel fraction: ", (funcInfo.complexity.parallelFraction * 100):int, "%");
                }
                
                if funcInfo.complexity.atomicOps > 0 {
                    writeln("    Atomic operations: ", funcInfo.complexity.atomicOps);
                }
                if funcInfo.complexity.syncPoints > 0 {
                    writeln("    Synchronization points: ", funcInfo.complexity.syncPoints);
                }
                if funcInfo.complexity.commCompRatio > 0 {
                    writeln("    Comm/Comp ratio: ", (funcInfo.complexity.commCompRatio * 100):int, "%");
                }
                if funcInfo.isGPUKernel {
                    writeln("    Estimated GPU occupancy: ", (funcInfo.complexity.gpuOccupancy * 100):int, "%");
                    writeln("    Coalesced accesses: ", funcInfo.complexity.coalescedAccess);
                    writeln("    Thread divergence: ", funcInfo.complexity.threadDivergence);
                }
                if funcInfo.complexity.cacheEfficiency > 0 {
                    writeln("    Cache efficiency: ", (funcInfo.complexity.cacheEfficiency * 100):int, "%");
                }
            }
        }
        
        if !found {
            writeln("No functions found with high cyclomatic complexity.");
        }
    }
    
    // Generate complete complexity report
    proc generateComplexityReport(): string {
        var report = "=== PROJECT COMPLEXITY REPORT ===\n\n";
        
        report = report + "Analysis configuration:\n";
        report = report + "- Directory: " + inputDir + "\n";
        report = report + "- Maximum depth: " + maxDepth:string + "\n";
        report = report + "- Parallelism analysis: " + showParallelism:string + "\n";
        report = report + "- Include GPU kernels: " + includeGPUKernels:string + "\n";
        report = report + "- Distributed analysis: " + distributedAnalysis:string + "\n\n";
        
        // General summary
        var totalFunctions = this.functions.size;
        var totalComplexity = 0;
        var parallelCount = 0;
        var gpuCount = 0;
        var distributedCount = 0;
        
        for funcName in this.functions.keys() {
            ref funcInfo = this.functions[funcName];
            totalComplexity = totalComplexity + funcInfo.complexity.cyclomaticComplexity;
            if funcInfo.isParallel then parallelCount = parallelCount + 1;
            if funcInfo.isGPUKernel then gpuCount = gpuCount + 1;
            if funcInfo.isDistributed then distributedCount = distributedCount + 1;
        }
        
        report = report + "EXECUTIVE SUMMARY:\n";
        report = report + "- Total functions: " + totalFunctions:string + "\n";
        report = report + "- Average complexity: " + (totalComplexity:real / totalFunctions:real):string + "\n";
        report = report + "- Parallel functions: " + parallelCount:string + " (" + 
                 (parallelCount:real / totalFunctions:real * 100):int:string + "%)\n";
        report = report + "- GPU kernels: " + gpuCount:string + "\n";
        report = report + "- Distributed functions: " + distributedCount:string + "\n\n";
        
        // Additional metrics for summary
        var avgMaintainability = 0.0;
        var avgFanIn = 0.0;
        var avgFanOut = 0.0;
        var avgParallelFraction = 0.0;
        var avgCacheEfficiency = 0.0;
        
        for funcName in this.functions.keys() {
            ref funcInfo = this.functions[funcName];
            avgMaintainability = avgMaintainability + funcInfo.complexity.maintainabilityIndex;
            avgFanIn = avgFanIn + funcInfo.complexity.fanIn:real;
            avgFanOut = avgFanOut + funcInfo.complexity.fanOut:real;
            avgParallelFraction = avgParallelFraction + funcInfo.complexity.parallelFraction;
            avgCacheEfficiency = avgCacheEfficiency + funcInfo.complexity.cacheEfficiency;
        }
        
        avgMaintainability = avgMaintainability / totalFunctions:real;
        avgFanIn = avgFanIn / totalFunctions:real;
        avgFanOut = avgFanOut / totalFunctions:real;
        avgParallelFraction = avgParallelFraction / totalFunctions:real;
        avgCacheEfficiency = avgCacheEfficiency / totalFunctions:real;
        
        report = report + "ADDITIONAL METRICS:\n";
        report = report + "- Average maintainability index: " + avgMaintainability:int:string + "\n";
        report = report + "- Average fan-in: " + avgFanIn:string + "\n";
        report = report + "- Average fan-out: " + avgFanOut:string + "\n";
        report = report + "- Average parallel fraction: " + (avgParallelFraction * 100):int:string + "%\n";
        report = report + "- Average cache efficiency: " + (avgCacheEfficiency * 100):int:string + "%\n\n";
        
        // Detailed function analysis
        report = report + "DETAILED FUNCTION ANALYSIS:\n\n";
        
        for funcName in this.functions.keys() {
            ref funcInfo = this.functions[funcName];
            report = report + "Function: " + funcName + "\n";
            report = report + "  File: " + funcInfo.filename + ":" + funcInfo.lineNumber:string + "\n";
            report = report + "  Cyclomatic complexity: " + funcInfo.complexity.cyclomaticComplexity:string + "\n";
            report = report + "  Algorithmic complexity: " + funcInfo.complexity.algorithmicComplexity + "\n";
            report = report + "  Memory complexity: " + funcInfo.complexity.memoryComplexity + "\n";
            report = report + "  Maintainability index: " + funcInfo.complexity.maintainabilityIndex:int:string + "\n";
            report = report + "  Fan-in: " + funcInfo.complexity.fanIn:string + 
                     ", Fan-out: " + funcInfo.complexity.fanOut:string + "\n";
            report = report + "  LOC: " + funcInfo.complexity.linesOfCode:string + 
                     ", Comments: " + funcInfo.complexity.commentLines:string + "\n";
            
            if funcInfo.isParallel {
                report = report + "  Parallelism type: " + funcInfo.complexity.parallelComplexity + "\n";
                report = report + "  Parallel fraction: " + (funcInfo.complexity.parallelFraction * 100):int:string + "%\n";
                if !funcInfo.parallelConstructs.isEmpty() {
                    report = report + "  Constructs: ";
                    var first = true;
                    for construct in funcInfo.parallelConstructs {
                        if !first then report = report + ", ";
                        report = report + construct;
                        first = false;
                    }
                    report = report + "\n";
                }
            }
            
            // Locality and scalability metrics
            if funcInfo.complexity.cacheEfficiency > 0 {
                report = report + "  Cache efficiency: " + (funcInfo.complexity.cacheEfficiency * 100):int:string + "%\n";
            }
            if funcInfo.complexity.commCompRatio > 0 {
                report = report + "  Comm/Comp ratio: " + (funcInfo.complexity.commCompRatio * 100):int:string + "%\n";
            }
            if funcInfo.complexity.loadBalance != 1.0 {
                report = report + "  Load balance: " + (funcInfo.complexity.loadBalance * 100):int:string + "%\n";
            }
            
            if funcInfo.complexity.atomicOps > 0 {
                report = report + "  Atomic operations: " + funcInfo.complexity.atomicOps:string + "\n";
            }
            if funcInfo.complexity.syncPoints > 0 {
                report = report + "  Synchronization points: " + funcInfo.complexity.syncPoints:string + "\n";
            }
            if funcInfo.complexity.distributedOps > 0 {
                report = report + "  Distributed operations: " + funcInfo.complexity.distributedOps:string + "\n";
            }
            
            // GPU-specific metrics
            if funcInfo.isGPUKernel {
                report = report + "  === GPU METRICS ===\n";
                report = report + "  Estimated occupancy: " + (funcInfo.complexity.gpuOccupancy * 100):int:string + "%\n";
                report = report + "  Coalesced accesses: " + funcInfo.complexity.coalescedAccess:string + "\n";
                report = report + "  Thread divergence: " + funcInfo.complexity.threadDivergence:string + "\n";
            }
            
            report = report + "\n";
        }
        
        return report;
    }
}

// Helper function to show usage
proc showHelp() {
    writeln("Chapel Call Graph Analyzer with Complexity Metrics");
    writeln("Usage: chapel_analyzer [options]");
    writeln();
    writeln("Basic options:");
    writeln("  --inputDir=<dir>         Chapel project directory (default: .)");
    writeln("  --outputFile=<file>      PikChr output file (default: call_graph.pikchr)");
    writeln("  --maxDepth=<n>           Maximum call graph depth (default: 3)");
    writeln("  --includeBuiltins        Include builtin functions in analysis");
    writeln();
    writeln("Complexity analysis options:");
    writeln("  --analyzeComplexity      Enable complexity analysis (default: true)");
    writeln("  --complexityMetrics      Show metrics in diagram (default: true)");
    writeln("  --showParallelism        Analyze parallel constructs (default: true)");
    writeln("  --includeGPUKernels      Include GPU kernel analysis (default: true)");
    writeln("  --distributedAnalysis    Analyze distributed operations (default: true)");
    writeln();
    writeln("Examples:");
    writeln("  # Basic analysis");
    writeln("  ./chapel_analyzer --inputDir=my_project --maxDepth=2");
    writeln();
    writeln("  # Full analysis with all metrics");
    writeln("  ./chapel_analyzer --inputDir=my_project --maxDepth=4 \\");
    writeln("                    --analyzeComplexity --showParallelism \\");
    writeln("                    --includeGPUKernels --distributedAnalysis");
    writeln();
    writeln("Metrics generated:");
    writeln("  - Cyclomatic Complexity (McCabe)");
    writeln("  - Algorithmic Complexity (Big O estimation)");
    writeln("  - Memory Complexity");
    writeln("  - Maintainability Index (Halstead + combined metrics)");
    writeln("  - Fan-in/Fan-out (Coupling)");
    writeln("  - Data Locality (Cache Efficiency)");
    writeln("  - Scalability (Amdahl's Law, Load Balance)");
    writeln("  - Parallelism Types (Data/Task/GPU/Distributed)");
    writeln("  - GPU Metrics (Occupancy, Coalescing, Divergence)");
    writeln("  - Atomic Operations and Synchronization");
    writeln("  - Domain and Locale Analysis");
    writeln();
    writeln("Outputs:");
    writeln("  - <outputFile>: Visualizable PikChr diagram");
    writeln("  - complexity_report.txt: Detailed metrics report");
    writeln();
    writeln("Interpretation ranges:");
    writeln("  - Maintainability: >85 (Excellent), 65-85 (Good), <65 (Problematic)");
    writeln("  - Fan-out: <7 (Good), 7-15 (Acceptable), >15 (High coupling)");
    writeln("  - Scalability: >70% parallel + <30% comm/comp = Good scalability");
}

// Main function
proc main(args: [] string) {
    // Check for help arguments
    for arg in args {
        if arg == "--help" || arg == "-h" {
            showHelp();
            return;
        }
    }
    
    writeln("=== Chapel Call Graph Analyzer ===");
    writeln("Input directory: ", inputDir);
    writeln("Output file: ", outputFile);
    writeln("Maximum depth: ", maxDepth);
    writeln("Include builtins: ", includeBuiltins);
    writeln("Complexity analysis: ", analyzeComplexity);
    writeln("Show parallelism: ", showParallelism);
    writeln("Include GPU kernels: ", includeGPUKernels);
    writeln("Complexity metrics: ", complexityMetrics);
    writeln("Distributed analysis: ", distributedAnalysis);
    writeln();
    
    // Create analyzer
    var analyzer = new CallGraphAnalyzer();
    
    // Analyze project
    analyzer.analyzeProject(inputDir);
    
    // Generate PikChr diagram
    //var diagram = analyzer.generatePikChrDiagram();
    
    // Save diagram
    //analyzer.saveDiagram(diagram, outputFile);
    
    // Print statistics
    analyzer.printStatistics();
    
    // Generate complexity report if enabled
    if complexityMetrics {
        var complexityReport = analyzer.generateComplexityReport();
        var reportFile = inputDir + "/complexity_report.txt";
        analyzer.saveDiagram(complexityReport, reportFile);
        writeln("Complexity report saved to: ", reportFile);
    }
    
    writeln("\nTo visualize the diagram:");
    writeln("1. Visit https://pikchr.org/home/pikchrshow");
    writeln("2. Copy the content of ", outputFile);
    writeln("3. Paste in the online editor to see the result");
    
    if analyzeComplexity {
        writeln("\nMetrics included in diagram:");
        writeln("- CC: Cyclomatic Complexity");
        writeln("- MI: Maintainability Index");
        writeln("- F: Fan-in/Fan-out");
        writeln("- C/C: Communication/Computation Ratio");
        writeln("- Occ: GPU Occupancy (for kernels)");
        writeln("- [PAR]: Functions with parallelism");
        writeln("- [GPU]: GPU kernels");
        writeln("- [DIST]: Distributed functions");
        writeln("- Different arrow colors by call type");
        
        writeln("\nMetric interpretation:");
        writeln("- MI > 85: Highly maintainable, MI 65-85: Maintainable, MI < 65: Hard to maintain");
        writeln("- High fan-out: Highly coupled function");
        writeln("- High fan-in: Heavily used function (potential critical point)");
        writeln("- Low C/C (<30%): Good scalability");
        writeln("- High GPU occupancy (>75%): Good GPU resource usage");
    }
}

// Entry point
//main(commandLineArguments);
