module common;
import std::collections::list;


List{Obj*} allocatedConstants;
bool allocatedConstantsInitialized = false;

fn void ensure_globals_init(){
    if(!allocatedConstantsInitialized){
        allocatedConstants.init(mem);
        allocatedConstantsInitialized=true;
    }
}
