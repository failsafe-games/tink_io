package tink.io;

import haxe.io.Bytes;
import tink.io.Sink;
import tink.io.Source;

using tink.CoreApi;

class Pipe {
  var buffer:Buffer;
  var source:Source;
  var dest:Sink;
	var result:FutureTrigger<PipeResult<Error, Error>>;
  
  function new(source, dest, ?buffer) {
    
    if (buffer == null)
      buffer = Buffer.alloc(17);
      
		this.source = source;
		this.dest = dest;
		
		this.buffer = buffer;
		this.result = Future.trigger();
		
  }
  
  function terminate(s)
    result.trigger(s);
  
	function read()
		source.read(buffer).handle(function (o) switch o {
			case Success(_.isEof => true):
        source.close();
        buffer.seal();
				flush();
			case Success(v):
        flush();
			case Failure(e):
        terminate(SourceFailed(e));
		});
    
	function flush() {
		dest.write(buffer).handle(function (o) switch o {
			case Success(_.isEof => true):
        terminate(if (buffer.available > 0) SinkEnded(buffer) else AllWritten);
			case Success(v):
				if (buffer.writable) //TODO: find a good threshold
					read();
				else 
					flush();
			case Failure(f):
				source.close();
        terminate(SinkFailed(f, buffer));
		});
	}	
  
  static var queue = [];
  
  static public function make<In, Out>(from:PipePart<In, Source>, to:PipePart<Out, Sink>, ?buffer):Future<PipeResult<In, Out>> {
		var p = new Pipe(from, to, buffer);
    p.read();
		var ret = p.result.asFuture();    
    
    ret.handle(function () {
      @:privateAccess p.buffer.dispose();
    });
      
    return cast ret;
  }
}

enum PipeResult<In, Out> {
  AllWritten:PipeResult<In, Out>;
  SinkFailed(e:Error, rest:Buffer):PipeResult<In, Error>;
  SinkEnded(rest:Buffer):PipeResult<In, Error>;
  SourceFailed(e:Error):PipeResult<Error, Out>;
}

abstract PipePart<Quality, Value>(Value) to Value {
  
  inline function new(x) this = x;
  
  @:from static inline function ofIdealSource(s:IdealSource)
    return new PipePart<Noise, Source>(s); 
    
  @:from static inline function ofSource(s:Source)
    return new PipePart<Error, Source>(s); 
    
  @:from static inline function ofIdealSink(s:IdealSink)
    return new PipePart<Noise, IdealSink>(s);
    
  @:from static inline function ofSink(s:Sink)
    return new PipePart<Error, Sink>(s); 
}