//
// Load every Lua file we ship on the real Kahlua, the VM the game runs.
//
// tests/kahlua-check.sh is a grep: it can tell that a file has no `goto` in it,
// but it cannot tell that Kahlua PARSES the file, and it cannot tell that the
// top-level statements RUN. luac5.1 -p is a different parser and a different
// runtime. So this takes se.krka.kahlua straight out of the game's jar,
// builds the environment the game builds (J2SEPlatform.newEnvironment), and
// loads our files in the game's own order.
//
// Kahlua is reached by reflection on purpose: the jar's class files are
// version 69 (Java 25) and the javac on this box is 21, so javac cannot see
// those classes at compile time at all. The class runs under the game's own
// jre64. Every reflected signature below is the one javap prints, quoted
// where it is used.
//
// Usage: java -cp <projectzomboid.jar>:tools/out KahluaRun <repo root>
//

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.TreeMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class KahluaRun {

	// The game's own load order, proven from the bytecode of
	// zombie.Lua.LuaManager: searchFolders() walks media/lua and adds each
	// path lowercased (String.toLowerCase(Locale.ENGLISH)) relative to the
	// lua root, then LoadDirBase() does
	//   Collections.sort(loadList, String.CASE_INSENSITIVE_ORDER)
	// before loading. So: case-insensitive sort of the relative paths.
	private static final Comparator<String> GAME_ORDER = String.CASE_INSENSITIVE_ORDER;

	// Files whose top level touches so much of the game that stubbing it all
	// would be a second game rather than a test. They are PARSED on Kahlua
	// and not run, and the report says so per file. Keeping this a short
	// named list is the point: a file nobody put here has to load for real.
	// As it turns out every file we ship runs its top level on the stubs
	// below, so the list is empty. It stays here because the first file whose
	// top level reaches deeper into the game belongs in it rather than in a
	// growing pile of stubs.
	private static final Set<String> PARSE_ONLY = new LinkedHashSet<>(List.<String>of());

	// ---- the Kahlua API, by the signatures javap prints -------------------

	private static Class<?> cPlatform;     // se.krka.kahlua.vm.Platform
	private static Class<?> cTable;        // se.krka.kahlua.vm.KahluaTable
	private static Class<?> cThread;       // se.krka.kahlua.vm.KahluaThread
	private static Class<?> cJavaFunction; // se.krka.kahlua.vm.JavaFunction
	private static Class<?> cFrame;        // se.krka.kahlua.vm.LuaCallFrame

	private static Method mLoadis;   // LuaCompiler.loadis(InputStream, String, KahluaTable)
	private static Method mCall;     // KahluaThread.call(Object, Object, Object, Object)
	private static Method mRawget;   // KahluaTable.rawget(Object)
	private static Method mRawset;   // KahluaTable.rawset(Object, Object)
	private static Method mIsFunc;   // KahluaUtil.isFunction(Object)
	private static Method mFrameGet; // LuaCallFrame.get(int)
	private static Method mPcall;    // KahluaThread.pcall(Object, Object[])

	private static Object env;
	private static Object thread;

	// require's cache, and the names it could not find among our own files --
	// a require of one of the game's files (Map/SGlobalObject) is a no-op
	// here and is reported rather than hidden.
	private static final Set<String> required = new LinkedHashSet<>();
	private static final Set<String> requiredForeign = new LinkedHashSet<>();

	private static Path root;
	private static int failures = 0;

	public static void main(String[] args) throws Exception {
		if (args.length != 1) {
			System.err.println("usage: KahluaRun <repo root>");
			System.exit(2);
		}
		root = Path.of(args[0]).toAbsolutePath().normalize();

		boot();

		List<String> shared = luaFiles("42/media/lua/shared");
		System.out.println("== shared on Kahlua (" + shared.size() + " files, game order)");
		for (String rel : shared) {
			load(rel);
		}

		System.out.println("== every CeroSecOS.* / CeroSec.* the server and client call exists");
		checkCalls();

		List<String> outer = new ArrayList<>();
		outer.addAll(luaFiles("42/media/lua/server"));
		outer.addAll(luaFiles("42/media/lua/client"));
		System.out.println("== server and client on Kahlua (" + outer.size() + " files, stubbed globals)");
		for (String rel : outer) {
			load(rel);
		}

		if (!requiredForeign.isEmpty()) {
			System.out.println("  note: require of the game's own files, no-op here: "
				+ String.join(", ", requiredForeign));
		}

		if (failures > 0) {
			System.out.println("kahlua-run: FAILED (" + failures + ")");
			System.exit(1);
		}
		System.out.println("kahlua-run: passed");
	}

	// ---- environment -----------------------------------------------------

	private static void boot() throws Exception {
		cPlatform = Class.forName("se.krka.kahlua.vm.Platform");
		cTable = Class.forName("se.krka.kahlua.vm.KahluaTable");
		cThread = Class.forName("se.krka.kahlua.vm.KahluaThread");
		cJavaFunction = Class.forName("se.krka.kahlua.vm.JavaFunction");
		cFrame = Class.forName("se.krka.kahlua.vm.LuaCallFrame");
		Class<?> cJ2SE = Class.forName("se.krka.kahlua.j2se.J2SEPlatform");
		Class<?> cCompiler = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler");
		Class<?> cUtil = Class.forName("se.krka.kahlua.vm.KahluaUtil");

		mLoadis = cCompiler.getMethod("loadis", InputStream.class, String.class, cTable);
		mCall = cThread.getMethod("call", Object.class, Object.class, Object.class, Object.class);
		mRawget = cTable.getMethod("rawget", Object.class);
		mRawset = cTable.getMethod("rawset", Object.class, Object.class);
		mIsFunc = cUtil.getMethod("isFunction", Object.class);
		mFrameGet = cFrame.getMethod("get", int.class);
		mPcall = cThread.getMethod("pcall", Object.class, Object[].class);

		// Exactly what zombie.Lua.LuaManager.init() does:
		//   platform = new J2SEPlatform();
		//   env = platform.newEnvironment();
		//   thread = new KahluaThread(platform, env);
		// newEnvironment() is newTable() + setupEnvironment(), and
		// setupEnvironment registers MathLib, BaseLib, RandomLib,
		// UserdataArray, StringLib, CoroutineLib, OsLib and TableLib, then
		// runs the game's own stdlib.lua -- which it reads as
		// new File("stdlib.lua").getAbsoluteFile(), so this has to run with
		// the game folder as the working directory. tests/kahlua-run.sh does
		// that; here we only check it, because the failure is otherwise a
		// bare RuntimeException.
		if (!new File("stdlib.lua").isFile()) {
			System.err.println("KahluaRun: no stdlib.lua in the working directory -- "
				+ "Kahlua's setupEnvironment() reads it from there. Run from the game folder.");
			System.exit(2);
		}
		Object platform = cJ2SE.getConstructor().newInstance();
		env = cJ2SE.getMethod("newEnvironment").invoke(platform);
		thread = cThread.getConstructor(cPlatform, cTable).newInstance(platform, env);
		// LuaManager.init() sets this too, and pcall() reads it: without it
		// pcall dies on debugOwnerThread.getName() before it runs anything.
		cThread.getField("debugOwnerThread").set(thread, Thread.currentThread());

		installRequire();
		runChunk(stubs(), "kahlua-run-stubs.lua");
	}

	// A require that mirrors the game's: it resolves a name to one of our
	// files under shared/, server/ or client/, loads it once, and is a no-op
	// the second time. A name that is none of ours is one of the game's own
	// files; we have not got it, so it is a no-op too and gets reported.
	private static void installRequire() throws Exception {
		InvocationHandler h = (proxy, method, margs) -> {
			if (!method.getName().equals("call")) {
				return method.getName().equals("toString") ? "require" : null;
			}
			Object name = mFrameGet.invoke(margs[0], 0);
			if (name instanceof String s) {
				requireName(s);
			}
			return 0; // no return values
		};
		Object require = Proxy.newProxyInstance(
			KahluaRun.class.getClassLoader(), new Class<?>[] { cJavaFunction }, h);
		mRawset.invoke(env, "require", require);
	}

	private static void requireName(String name) throws Exception {
		String key = name.replace('\\', '/').toLowerCase();
		if (key.endsWith(".lua")) {
			key = key.substring(0, key.length() - 4);
		}
		if (!required.add(key)) {
			return;
		}
		for (String dir : new String[] { "shared", "server", "client" }) {
			Path p = root.resolve("42/media/lua/" + dir + "/" + name + ".lua");
			Path found = caseInsensitive(root.resolve("42/media/lua/" + dir), p);
			if (found != null) {
				load(root.relativize(found).toString());
				return;
			}
		}
		requiredForeign.add(name);
	}

	// The game's file system is case-insensitive about lua paths (it
	// lowercases them); ours is not, so match the lowercased path.
	private static Path caseInsensitive(Path base, Path wanted) throws Exception {
		if (Files.isRegularFile(wanted)) {
			return wanted;
		}
		if (!Files.isDirectory(base)) {
			return null;
		}
		String want = wanted.toString().toLowerCase();
		try (var walk = Files.walk(base)) {
			return walk.filter(Files::isRegularFile)
				.filter(p -> p.toString().toLowerCase().equals(want))
				.findFirst().orElse(null);
		}
	}

	// The game globals our server and client files touch WHILE THEY LOAD --
	// nothing else. Every name here was put there by an actual load-time
	// error, one at a time, and the list is meant to stay this short: a file
	// that wants more than this belongs in PARSE_ONLY above.
	//
	//   isClient / isServer   the first line of every S*.lua file
	//   Events                Events.OnWhatever.Add(f) at the bottom of the
	//                         menu and system files
	//   getText               a few menu labels built at load time
	//   the six class roots   X = <root>:derive("X"), two of them also with
	//                         RegisterSystemClass()
	//   MapObjects            the sprite registry the system files write to
	//
	private static String stubs() {
		return String.join("\n",
			"isClient = function() return false end",
			"isServer = function() return false end",
			"",
			"-- One event object behind every Events.OnWhatever.",
			"local event = { Add = function() end, Remove = function() end }",
			"Events = setmetatable({}, { __index = function(t, k) t[k] = event return event end })",
			"",
			"getText = function(k) return tostring(k) end",
			"",
			"-- A class root of the game's shape: derive() makes a child that",
			"-- derives and news in turn, which is all a load-time",
			"-- `X = <root>:derive(\"X\")` needs.",
			"local function class(name)",
			"	local c = {}",
			"	c.Type = name",
			"	c.derive = function(self, childName)",
			"		local child = class(childName)",
			"		child.__index = child",
			"		setmetatable(child, { __index = self })",
			"		return child",
			"	end",
			"	c.new = function(self) return setmetatable({}, { __index = self }) end",
			"	return c",
			"end",
			"ISBaseObject = class(\"ISBaseObject\")",
			"local function registrar(c) c.RegisterSystemClass = function() end return c end",
			"ISCollapsableWindow = class(\"ISCollapsableWindow\")",
			"ISBaseTimedAction = class(\"ISBaseTimedAction\")",
			"SGlobalObject = class(\"SGlobalObject\")",
			"SGlobalObjectSystem = registrar(class(\"SGlobalObjectSystem\"))",
			"CGlobalObject = class(\"CGlobalObject\")",
			"CGlobalObjectSystem = registrar(class(\"CGlobalObjectSystem\"))",
			"",
			"-- The sprite registry the two system files hand their loader to.",
			"MapObjects = { OnNewWithSprite = function() end, OnLoadWithSprite = function() end }",
			"");
	}

	// ---- loading ---------------------------------------------------------

	private static List<String> luaFiles(String relDir) throws Exception {
		Path dir = root.resolve(relDir);
		List<String> out = new ArrayList<>();
		try (var walk = Files.walk(dir)) {
			walk.filter(Files::isRegularFile)
				.filter(p -> p.toString().endsWith(".lua"))
				.forEach(p -> out.add(root.relativize(p).toString()));
		}
		// Sorted on the path relative to the lua root, the way the game does.
		out.sort((a, b) -> GAME_ORDER.compare(
			a.substring("42/media/lua/".length()), b.substring("42/media/lua/".length())));
		return out;
	}

	// Load a file the way the harness is set up to: run it, or parse it only
	// if it is on the named list.
	private static void load(String rel) {
		if (PARSE_ONLY.contains(rel.substring("42/media/lua/".length()).replace('\\', '/'))) {
			parseOnly(rel);
		} else {
			loadForReal(rel);
		}
	}

	private static void loadForReal(String rel) {
		if (!loaded.add(rel)) {
			return; // a second require is a no-op, as in the game
		}
		Object closure = compile(rel);
		if (closure == null) {
			return;
		}
		// pcall, not call: KahluaThread.pcall(Object, Object[]) hands back
		// { false, message, "at <file>:<line>", exception } on an error, and
		// that third value is the only place Kahlua puts the LINE of a
		// runtime error -- the exception message names the file and nothing
		// else, and the call frame is already unwound by the time we catch.
		try {
			Object[] r = (Object[]) mPcall.invoke(thread, closure, new Object[0]);
			if (r != null && r.length > 0 && Boolean.FALSE.equals(r[0])) {
				fail(rel, "run", value(r, 1), value(r, 2));
			} else {
				System.out.println("  ok   " + rel);
			}
		} catch (InvocationTargetException e) {
			fail(rel, "run", message(e.getCause()), null);
		} catch (Exception e) {
			fail(rel, "run", message(e), null);
		}
	}

	private static String value(Object[] r, int i) {
		return i < r.length && r[i] != null ? String.valueOf(r[i]).trim() : null;
	}

	private static String message(Throwable t) {
		return t == null ? "(no message)" : t.getClass().getName() + ": " + t.getMessage();
	}

	private static void parseOnly(String rel) {
		if (!loaded.add(rel)) {
			return;
		}
		if (compile(rel) != null) {
			System.out.println("  ok   " + rel + "  (parsed only: its top level needs the game)");
		}
	}

	private static final Set<String> loaded = new LinkedHashSet<>();

	private static Object compile(String rel) {
		Path p = root.resolve(rel);
		// The chunk name the game uses is the path; Kahlua puts it in every
		// error message, so this is what makes a failure findable.
		try (InputStream in = new FileInputStream(p.toFile())) {
			return mLoadis.invoke(null, in, rel, env);
		} catch (InvocationTargetException e) {
			// A Kahlua compile error carries "<file>:<line>: <what>" in its
			// own message, so there is nothing to add to it.
			fail(rel, "compile", message(e.getCause()), null);
			return null;
		} catch (Exception e) {
			fail(rel, "compile", message(e), null);
			return null;
		}
	}

	private static void runChunk(String source, String name) throws Exception {
		Object closure = mLoadis.invoke(null,
			new java.io.ByteArrayInputStream(source.getBytes(StandardCharsets.UTF_8)), name, env);
		mCall.invoke(thread, closure, null, null, null);
	}

	private static void fail(String rel, String what, String msg, String where) {
		failures++;
		System.out.println("  FAIL " + rel + " does not " + what + " on Kahlua");
		System.out.println("       " + (msg == null ? "(no message)" : msg));
		if (where != null && !where.isEmpty()) {
			System.out.println("       " + where);
		}
	}

	// ---- the assertion on the engine's surface ---------------------------

	// Same idea as tests/selfcalls-check.sh, one step out: the server and
	// client call into the engine by name, and a name that is not there is a
	// nil call the moment that line runs in the game. The game reported
	// exactly that ("Object tried to call nil") the day this was written.
	private static void checkCalls() throws Exception {
		Pattern[] pats = {
			Pattern.compile("\\bCeroSecOS\\.([A-Za-z_]+)\\s*\\("),
			Pattern.compile("\\bCeroSec\\.([A-Za-z_]+)\\s*\\("),
		};
		// name -> first file that calls it
		TreeMap<String, String> wantOS = new TreeMap<>();
		TreeMap<String, String> wantDefs = new TreeMap<>();
		List<String> files = new ArrayList<>();
		files.addAll(luaFiles("42/media/lua/server"));
		files.addAll(luaFiles("42/media/lua/client"));
		for (String rel : files) {
			String src = Files.readString(root.resolve(rel), StandardCharsets.UTF_8);
			for (int i = 0; i < pats.length; i++) {
				Matcher m = pats[i].matcher(src);
				while (m.find()) {
					(i == 0 ? wantOS : wantDefs).putIfAbsent(m.group(1), rel);
				}
			}
		}
		int checked = 0;
		checked += assertFunctions("CeroSecOS", wantOS);
		checked += assertFunctions("CeroSec", wantDefs);
		System.out.println("  ok   " + checked + " engine functions called from server/client exist");
	}

	private static int assertFunctions(String tableName, TreeMap<String, String> want) throws Exception {
		Object table = mRawget.invoke(env, tableName);
		if (table == null || !cTable.isInstance(table)) {
			failures++;
			System.out.println("  FAIL " + tableName + " is not a table after loading shared");
			return 0;
		}
		int n = 0;
		for (var e : want.entrySet()) {
			Object v = mRawget.invoke(table, e.getKey());
			if (!(Boolean) mIsFunc.invoke(null, v)) {
				failures++;
				System.out.println("  FAIL " + tableName + "." + e.getKey()
					+ "() is called from " + e.getValue() + " and is not a function in the engine");
			}
			n++;
		}
		return n;
	}
}
