import Foundation

struct Env
{
    let args: [String]
    var argsSet: Set<String> { return Set(args) }
    var isHelp: Bool { return !argsSet.isDisjoint(with: ["-h", "--help"]) }
    var isVerbose: Bool { return !argsSet.isDisjoint(with: ["-v", "--verbose"]) }
    var isNoUser: Bool { return !argsSet.isDisjoint(with: ["--no-user"]) } // no substitution
    var noUpload: Bool { return !argsSet.isDisjoint(with: ["--no-upload"]) } // don't upload to the server
    var needMapping: Bool { return mapName != nil } // will do a search and replace step
    var mapName: String?
    {
        guard let userIndex = args.firstIndex(of: "--map"), args.indices.contains(userIndex + 1) else { return nil }
        return args[userIndex + 1]
    }

    var username: String?
    {
        guard
            let userIndex = indexOfParams(names: ["-u", "--user"]),
            args.indices.contains(userIndex + 1)
        else { return nil }
        return args[userIndex + 1]
    }

    private func indexOfParams(names: Set<String>) -> Int?
    {
        return args
            .enumerated()
            .filter { names.contains($0.element) }
            .map(\.offset)
            .first
    }

    let currentDirectory: URL
    let uploadFileDirectory: URL

    init(args: [String]) throws
    {
        self.args = args
        currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        uploadFileDirectory = currentDirectory.appendingPathComponent("__processed")
        print("Working in current directory: \(currentDirectory)")
        print("uploadFileDirectory directory: \(uploadFileDirectory)")

        if isVerbose
        {
            print("---------------")
            print("Environment for execution:")
            dump(self)
            print("---------------")
        }

        try prepareUploadDirectory()
    }

    private func prepareUploadDirectory() throws
    {
        if isHelp { return }

        if FileManager.default.fileExists(atPath: uploadFileDirectory.path)
        {
            if isVerbose
            {
                print("Will removeItem uploadFileDirectory: \(uploadFileDirectory)")
            }
            try FileManager.default.removeItem(at: uploadFileDirectory)
        }

        print("Will create uploadFileDirectory")
        try FileManager.default.createDirectory(at: uploadFileDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    func printHelp()
    {
        let help = """


        =========================
        Help

        -h --help           print this help
        -v --verbose        print more information to the console while running
        -u <String>         Username to replace %%username%% in input file
        --no-user           No username is provided on purpose
        --map <String>      Filename in current directory that contain replacement string to apply to input file name
        --no-upload         Skip the upload phase, will generate output

        # Timming
        copyFileForProcessing
        mapIfNeeded
        updateUsernameIfNeeded
        uploadAPIResponses

        # Output
        All .json file will be copied into the directory at \(uploadFileDirectory)
        The output directory is deleted at the begining of the scrip for cleanup

        # Map format
        Only line with this format will be processed:
        text_to_replace => replacement


        """
        print(help)
    }
}

func jsonURLsAt(_ url: URL) throws -> [URL]
{
    let folderContent = try FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
    )
    let jsonURLs =
        try folderContent
            .filter { $0.pathExtension.lowercased() == "json" }
            .map { try URL(resolvingAliasFileAt: $0) }
    return jsonURLs
}

func copyFileForProcessing(env: Env) throws
{
    print("Will copy input file to upload directory")
    let jsonURLs = try jsonURLsAt(env.currentDirectory)
    try jsonURLs.forEach
    { jsonURL in
        let saveURL = env.uploadFileDirectory.appendingPathComponent(jsonURL.lastPathComponent)
        try FileManager.default.copyItem(at: jsonURL, to: saveURL)
    }
}

func mapIfNeeded(env: Env) throws
{
    guard let mapFileName = env.mapName
    else
    {
        print("No Mapping file to process")
        return
    }

    let mapFileURL = try URL(resolvingAliasFileAt: env.currentDirectory.appendingPathComponent(mapFileName))
    print("Will Replace information in files based on map file: \(mapFileURL)")
    let inputLines = try String(contentsOf: mapFileURL, encoding: .utf8).components(separatedBy: .newlines)
    let mapLinesComponents: [[String]] = inputLines.compactMap
    {
        let components = $0.components(separatedBy: " => ")
        guard components.count > 1 else { return nil }
        return components.map
        {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    if env.isVerbose
    {
        print("Mapping content is: \(mapLinesComponents)")
    }

    let jsonURLs = try jsonURLsAt(env.uploadFileDirectory)
    try jsonURLs.forEach
    { jsonURL in
        let input = try String(contentsOf: jsonURL, encoding: .utf8)
        let result = mapLinesComponents.reduce(input)
        { acc, components in
            return acc.replacingOccurrences(of: components[0], with: components[1])
        }
        try result.write(to: jsonURL, atomically: true, encoding: .utf8)
    }
}

func updateUsernameIfNeeded(env: Env) throws
{
    if env.isNoUser
    {
        print("No user was specified")
        return
    }
    guard let username = env.username
    else
    {
        throw NSError(domain: "missing-user", code: -1, userInfo: [NSLocalizedDescriptionKey: "You must provide a user parameter for substitution"])
    }

    let userKey = "%%username%%"
    print("Will update '\(userKey)' with username '\(username)'")

    let jsonURLs = try jsonURLsAt(env.uploadFileDirectory)
    try jsonURLs.forEach
    { jsonURL in
        let str = try String(contentsOf: jsonURL, encoding: .utf8).replacingOccurrences(of: userKey, with: username)
        try str.write(to: jsonURL, atomically: true, encoding: .utf8)
    }
}

func uploadAPIResponses(env: Env) throws
{
    if env.noUpload {
        print("No Upload")
        return
    }

    let generatedFolderContent = try FileManager.default.contentsOfDirectory(
        at: env.uploadFileDirectory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
    )
    let generatedJsonURLs = generatedFolderContent.filter { $0.pathExtension.lowercased() == "json" }

    print("Will process URLs:\n\(generatedJsonURLs.map(\.description).joined(separator: "\n"))\n")

    let host = "127.0.0.1" // TODO: have a parameter to configure this
    let port = "8080" // TODO: have a parameter to configure this
    let url = URL(string: "http://\(host):\(port)/mocks")!

    let resetURL = url.appendingPathComponent("resetAll")
    var resetRequest = URLRequest(url: resetURL, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: 120)
    resetRequest.httpMethod = "DELETE"
    let sem = DispatchSemaphore(value: 0)
    var error: Error?
    print("Will remove all previous mocked call. URL: \(resetURL)")
    URLSession
        .shared
        .dataTask(with: resetRequest)
        { data, response, err in
            error = err
            if let err = err
            {
                print("Error removing previous mocked call: \(err.localizedDescription)")
            }

            if let httpResponse = response as? HTTPURLResponse
            {
                print("Response: \(httpResponse.statusCode)")
                if env.isVerbose
                {
                    print("------")
                    dump(httpResponse)
                    print("------")
                    if let data = data
                    {
                        let responseData = String(data: data, encoding: .utf8) ?? "Problem with response data decoding"
                        print("responseData => \(responseData)")
                        print("------")
                    }
                }
            }
            print("Done removing previous calls")
            sem.signal()
        }
        .resume()

    _ = sem.wait(timeout: DispatchTime.distantFuture)
    if let e = error
    {
        throw e
    }

    print("Will upload mock data to: \(url)")
    generatedJsonURLs.forEach
    { jsonURL in
        print("Processing URL: \(jsonURL)")
        guard let data = FileManager.default.contents(atPath: jsonURL.path) else { return }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: request)
        { data, response, error in
            if let error = error
            {
                print("Problem processing: \(jsonURL)")
                print("error: \(error.localizedDescription)")
            }

            if let httpResponse = response as? HTTPURLResponse
            {
                switch httpResponse.statusCode
                {
                case 200:
                    print("Response: \(httpResponse.statusCode)")
                default:
                    print("🛑 ❌ Response: \(httpResponse.statusCode) ‼️ ")
                }
                if env.isVerbose
                {
                    print("------")
                    dump(httpResponse)
                    print("------")
                    if let data = data
                    {
                        let responseData = String(data: data, encoding: .utf8)
                        print(responseData ?? "Problem with response data decoding")
                        print("------")
                    }
                }
            }

            let millisecond: useconds_t = 1000
            usleep(100 * millisecond)

            print("Done processing: \(jsonURL)")
            semaphore.signal()
        }
        .resume()

        _ = semaphore.wait(timeout: DispatchTime.distantFuture)
    }
}

// MARK: - main
do
{
    let env = try Env(args: CommandLine.arguments)
    if env.isHelp
    {
        env.printHelp()
        exit(0)
    }

    try copyFileForProcessing(env: env)
    try mapIfNeeded(env: env)
    try updateUsernameIfNeeded(env: env)
    try uploadAPIResponses(env: env)
}
catch
{
    print("PROBLEM: \(error.localizedDescription)")
    print("\n\nrun --help command for manual and -v for verbose mode\n\n")
}
