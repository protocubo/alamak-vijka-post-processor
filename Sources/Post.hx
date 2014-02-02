import format.ett.Data;

typedef OD = elebeta.ett.vijka.OD;

typedef ODResult = elebeta.ett.vijka.ODResult;

class Result {
	public var placement(default,null):String;
	public var vehicle(default,null):Int;
	public var scenario(default,null):String;
	public var all(default,null):Float;
	public var escaped(default,null):Float;

	public function new( placement, vehicle, scenario, all, escaped ) {
		this.placement = placement;
		this.vehicle = vehicle;
		this.scenario = scenario;
		this.all = all;
		this.escaped = escaped;
	}

	public function sum( r:Result ):Result {
		return new Result( placement, vehicle, scenario, all + r.all, escaped + r.escaped );
	}

	public function sub( r:Result ):Result {
		return new Result( placement, vehicle, scenario, all - r.all, escaped - r.escaped );
	}	
}

typedef KeyComponents = {
	var placement:String;
	var scenario:String;
}

typedef Aggregate = Result;

class AggregateCollection {

	private var data:Map<String,Aggregate>;

	public function new() {
		data = new Map();
	}

	public function get( placement, vehicle, scenario ) {
		return data.get( key( placement, vehicle, scenario ) );
	}

	public function add( a:Aggregate ) {
		var k = key( a.placement, a.vehicle, a.scenario );
		if ( data.exists( k ) )
			data.set( k, data.get( k ).sum( a ) );
		else
			data.set( k, a );
	}

	public function map( f:Aggregate->Aggregate ) {
		var n = new AggregateCollection();
		for ( a in data )
			n.add( f(a) );
		return n;
	}

	public function iterator() {
		return data.iterator();
	}

	private function key( placement, vehicle:Int, scenario ) {
		return placement+"_"+vehicle+"_"+scenario;
	}

}

class Post {

	public static function parseKey( key:String ) {
		var s = key.split( "_" );
		return { placement:s.slice(0,2).join("_"), scenario:s.slice(2,4).join("_") };
	}

	public static function result( ods:Map<Int,OD>, odr:ODResult ) {
		var od = ods.get( odr.odId );
		if ( od == null )
			throw "No survey data for `"+odr.odId+"`";
		var kc = parseKey( odr.key );
		#if USE_WEIGHTS
		return new Result( kc.placement, od.vehicleId, kc.scenario, odr.weight, odr.escaped ? odr.weight : 0. );
		#else
		return new Result( kc.placement, od.vehicleId, kc.scenario, 1., odr.escaped ? 1. : 0. );
		#end
	}

	public static function makeAggrCol( res:Iterable<Result> ) {
		var ac = new AggregateCollection();
		for ( r in res )
			ac.add( r );
		return ac;
	}

	public static function aggrFix( aggrCol:AggregateCollection, basis, a:Aggregate ) {
		var x = aggrCol.get( a.placement, a.vehicle, basis );
		if ( x == null )
			throw "No basis data for placement,vehicle,scenario `"+a.placement+"`,`"+a.vehicle+"`,`"+basis+"`";
		return new Aggregate( a.placement, a.vehicle, a.scenario, a.all - x.escaped, a.escaped - x.escaped );
	}

	public static function loadOds( stream:haxe.io.Input ) {
		var f = new format.ett.Reader( stream );
		if ( f.info.className != "elebeta.ett.vijka.OD" )
			throw "Wrong ETT file class for OD `"+f.info.className+"`";
		var res = new Map();
		try while ( true ) {
			var r = f.fastReadRecord( OD.makeEmpty() );
			res.set( r.id, r );
		}
		catch ( e:haxe.io.Eof ) {}
		return res;
	}

	public static function loadOdResults( stream:haxe.io.Input ) {
		var f = new format.ett.Reader( stream );
		if ( f.info.className != "elebeta.ett.vijka.ODResult" )
			throw "Wrong ETT file class for ODResult `"+f.info.className+"`";
		var res = new Array();
		try while ( true ) res.push( f.fastReadRecord( ODResult.makeEmpty() ) )
		catch ( e:haxe.io.Eof ) {}
		return res;
	}

	public static function ettAggregates( stream:haxe.io.Output, aggrCol:AggregateCollection ) {
		var fields = [
			new Field( "placement", TString ),
			new Field( "vehicle", TInt ),
			new Field( "scenario", TString ),
			new Field( "all", TFloat ),
			new Field( "escaped", TFloat )
		];
		var finfo = new FileInfo( "\n", UTF8, "\t", "'", "", fields );
		var wter = new format.ett.Writer( finfo );
		wter.prepare( stream );
		var data = Lambda.array( aggrCol );
		data.sort( function (a,b) return Reflect.compare(a.placement,b.placement)*16+Reflect.compare(a.vehicle,b.vehicle)*8+Reflect.compare(a.scenario,b.scenario)*1 );
		for ( x in data )
			wter.write( x );
	}

	private static function readFile( path, binary ) {
		if ( !sys.FileSystem.exists( path ) )
			throw "Cannot read, file `"+path+"` does not exist";
		else if ( sys.FileSystem.isDirectory( path ) )
			throw "Cannot read, `"+path+"` is a directory";
		else
			return sys.io.File.read( path, binary );
	}

	private static function eprint( v:Dynamic ) {
		Sys.stderr().writeString( Std.string( v ) );
	}

	private static function eprintln( v:Dynamic ) {
		eprint( v );
		eprint( "\n" );
	}

	private static function main() {
		haxe.Log.trace = function ( m, ?p ) eprintln( m );

		var args = Sys.args();
		if ( args.length < 1 || args.length > 2 )
			throw "Invalid number of arguments, expecting survey path and, optionally, basis";
		var odPath = args[0];
		var basis = args[1];

		eprintln( "Loading survey data" );
		var ods = loadOds( readFile( odPath, false ) );
		eprintln( "Loading results" );
		var odResults = loadOdResults( Sys.stdin() );

		eprintln( "Aggregating" );
		var aggrCol = makeAggrCol( odResults.map( result.bind( ods ) ) );
		if ( basis != null ) {
			eprintln( "Recomputing aggregates excluding pairs that escape on the basis scenarios" );
			var corr = aggrCol.map( aggrFix.bind( aggrCol, basis ) );
			eprintln( "Writing output" );
			ettAggregates( Sys.stdout(), corr );
		}
		else {
			eprintln( "Writing output" );
			ettAggregates( Sys.stdout(), aggrCol );
		}
	}

}
