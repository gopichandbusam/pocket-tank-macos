/* Regression for the real pthread/pending dispatch implementation, with an
   isolated deterministic inference stub; no model file, tank save or UI. */
#define _POSIX_C_SOURCE 200809L
#include <time.h>
#include <stdio.h>
#include "../../sim/advisor_llm.c"
bool advisor_core_sample=true;
float advisor_core_temp=1;
bool advisor_core_init(const uint8_t*a,size_t b,const uint8_t*c,size_t d,void*(*e)(size_t),uint32_t f){return true;}
int advisor_core_schema(void){return 4;}
void advisor_core_encode(const tank_t*t,int i,char*out,size_t n){snprintf(out,n,"%d",i);}
static pthread_mutex_t gate_mx=PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t gate_cv=PTHREAD_COND_INITIALIZER;
static bool gate_enabled, release_worker;
goal_t advisor_core_infer(const char*s,int*tokens){
 pthread_mutex_lock(&gate_mx);while(gate_enabled&&!release_worker)pthread_cond_wait(&gate_cv,&gate_mx);pthread_mutex_unlock(&gate_mx);goal_t g={0};g.id=atoi(s)?GOAL_REST:GOAL_EXPLORE;g.confidence=1;g.runner_up=GOAL_COUNT;return g;}
const float*advisor_core_last_probs(void){static float p[GOAL_COUNT];return p;}
const char *const GOAL_NAMES[GOAL_COUNT]={"stub"};
static bool await_response(int who){for(int k=0;k<1000;k++){pthread_mutex_lock(&g_mx);bool yes=g_resp_fish==who;pthread_mutex_unlock(&g_mx);if(yes)return true;struct timespec ts={0,1000000};nanosleep(&ts,0);}return false;}
int unread_test(void){tank_t t={0};t.n_fish=2;g_loaded=true;pthread_t th;pthread_create(&th,0,worker,0);
 advisor_llm(&t,0,true);if(!await_response(0))return 2;
 advisor_llm(&t,1,true);
 pthread_mutex_lock(&g_mx);bool retained=g_resp_fish==0 && g_pending[1] && g_req_fish<0 && !g_busy;pthread_mutex_unlock(&g_mx);
 if(!retained){puts("FAIL second dispatch permitted before unread first response consumed");return 1;}
 goal_t first=advisor_llm(&t,0,false);advisor_llm(&t,1,false);
 if(first.id!=GOAL_EXPLORE||!await_response(1))return 3;
 goal_t second=advisor_llm(&t,1,false);if(second.id!=GOAL_REST)return 4;
 puts("PASS unread decision retained; pending second fish delivered afterward");return 0;}

static bool await_busy(void){for(int k=0;k<1000;k++){pthread_mutex_lock(&g_mx);bool yes=g_busy;pthread_mutex_unlock(&g_mx);if(yes)return true;struct timespec ts={0,1000000};nanosleep(&ts,0);}return false;}
static int roster_test(bool inflight, bool reindexed){
 tank_t t={0};t.n_fish=reindexed?3:2;g_loaded=true;gate_enabled=inflight;
 pthread_t th;pthread_create(&th,0,worker,0);advisor_llm(&t,1,true);
 if(inflight){if(!await_busy())return 2;}else if(!await_response(1))return 2;
 /* Sell a last fish (response slot falls outside the new roster), or sell a
    preceding fish (old slot is now a different fish). Change happens while
    the worker has captured the old generation, before it can publish. */
 t.n_fish--;t.roster_gen++;advisor_llm(&t,0,true);
 if(inflight){pthread_mutex_lock(&gate_mx);release_worker=true;pthread_cond_signal(&gate_cv);pthread_mutex_unlock(&gate_mx);if(!await_response(1))return 3;}
 goal_t remaining=advisor_llm(&t,0,false);
 if(remaining.id!=t.fish[0].goal.id)return 4; /* never deliver the removed fish's result */
 if(!await_response(0)){puts("FAIL stale roster response blocked future dispatch");return 1;}
 advisor_llm(&t,0,false);
 if(reindexed){advisor_llm(&t,1,true);if(!await_response(1))return 5;goal_t fresh=advisor_llm(&t,1,false);if(fresh.id!=GOAL_REST)return 6;}
 puts("PASS stale roster decision dropped and current fish dispatch resumed");return 0;
}
int main(int argc,char **argv){
 if(argc<2||!strcmp(argv[1],"unread"))return unread_test();
 if(!strcmp(argv[1],"removed-inflight"))return roster_test(true,false);
 if(!strcmp(argv[1],"reindexed-inflight"))return roster_test(true,true);
 if(!strcmp(argv[1],"removed-completed"))return roster_test(false,false);
 return 7;
}
