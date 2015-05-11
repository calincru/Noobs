#!/bin/rdmd
import std.stdio, std.file, std.process, std.string, std.conv, std.algorithm,
       std.range, std.exception, std.typecons, std.path, std.random, std.parallelism, std.mathspecial;
enum usage = `
Usage: ./noobs.d bot1 bot2`;


string[string] load_config()
{
    enum defaults = [
    "map_folder": "warmaps",
    "warengine_folder": "warlight2-engine",
    "warengine_command": `java -cp lib/java-json.jar:bin com.theaigames.game.warlight2.Warlight2 "%s" "%s" "%s" "%s"`
    ];

    string[string] ret;
    try {
        auto ret_str = (cast(string) File("noobs.conf").byChunk(4096).front) .filter!`a != '\n'`.array;
        ret = ret_str.to!(string[string]);
        foreach (key; setDifference(defaults.keys, ret.keys))
            ret[key] = defaults[key];
    }
    catch (Exception e) {
        if (cast(ErrnoException) e)
            writeln("Could not open noobs.conf");
        else
            writeln("Could not parse config file");
        ret = defaults;
    }
    return ret;
}

void test_execution(string[string] config)
{
    try {
        auto ret = executeShell(config["warengine_command"].format("", "", "", ""),
                null, Config.none, 4096, config["warengine_folder"]);
        if (!canFind(ret.output, "parseLong"))
            throw new Exception(ret.output);
    }
    catch (Exception e)
        throw new Exception("Warengine test execution failed:\n" ~ e.msg);
}

auto get_bots(string[] args)
{
    if (args.length != 3)
        throw new Exception("Invalid arguments" ~ usage);
    Tuple!(string, "bot1", string, "bot2") ret;
    ret.bot1 = args[1];
    ret.bot2 = args[2];
    return ret;
}

void main(string[] args) {
    auto bots = get_bots(args);
    string[] mapfiles;
    auto config = load_config();
    try mapfiles = dirEntries(config["map_folder"], SpanMode.shallow).map!"a.name".array;
        catch throw new Exception("Could not open folder " ~ config["map_folder"]);
    test_execution(config);
    if (!bots.bot1.exists)
        throw new Exception("File " ~ bots.bot1 ~ " does not exist");
    if (!bots.bot2.exists)
        throw new Exception("File " ~ bots.bot2 ~ " does not exist");

    writeln("Available maps: " ~ mapfiles.length.to!string);
    File err_log = File("errors.log", "wb");

    int err_cnt, win1_cnt, game_cnt;
    bool first_time = true;
    writeln();
    foreach (mapfile; taskPool.parallel(mapfiles, 10)) {
        int seed = uniform(0, int.max);
        foreach (swap; [false, true]) {
            auto path1 = absolutePath(bots.bot1);
            auto path2 = absolutePath(bots.bot2);
            auto pathmap = absolutePath(mapfile);
            auto command = config["warengine_command"]
                .format(pathmap, swap ? path2 : path1, swap ? path1 : path2, seed);
            auto pipes = pipeShell(command, Redirect.all, null, Config.none,
                    config["warengine_folder"]);
            auto command_output = cast(string) pipes.stdout.byChunk(4096).front;
            auto command_err = cast(string) pipes.stderr.byChunk(4096).front;
            if (!canFind(command_output, "winner: ")) {
                ++err_cnt;
                err_log.writefln("Error in execution: %s\n%s\n", command, command_err);
            } else {
                ++game_cnt;
                if ((canFind(command_output, "winner: player1") && !swap)
                        || (canFind(command_output, "winner: player2") && swap))
                    ++win1_cnt;
            }
            auto win2_cnt = game_cnt - win1_cnt;
            if (first_time)
                first_time = false;
            else
                write("\r\b\r\b\r\b\r");
            writefln("1st bot (%s): %s winrate %s/%s ", bots.bot1,
                    winrate(win1_cnt, game_cnt), win1_cnt, game_cnt);
            writefln("2nd bot (%s): %s winrate %s/%s ", bots.bot2,
                    winrate(win2_cnt, game_cnt), win2_cnt, game_cnt);
            writefln("Error count: %s", err_cnt);
        }
    }
}

string winrate(int win, int total) {
    auto ci = binomial_ci(win, total, 0.05);
    if (total == 0)
        return "50.0 (0.0 - 100.0)";
    else
        return "%.1f%% (%.1f - %.1f)".format(100. * win/total, 100. * ci[0], 100. * ci[1]);
};

auto binomial_ci(double k, double n, double err) {
    double z = normalDistributionInverse(1-0.5*err);
    double p = 1.*k/n;
    double coef = 1/(1+(1/n)*z*z);
    double center = coef*(p+1/(2*n)*z*z);
    double offset = coef*z*sqrt(1/n*p*(1-p)+1/(4*n*n)*z*z);
    return tuple(center-offset, center+offset);
}
