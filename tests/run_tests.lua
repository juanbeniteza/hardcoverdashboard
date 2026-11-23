package.path="./hardcoverdashboard.koplugin/?.lua;./hardcoverdashboard.koplugin/?/init.lua;"..package.path
local D=require("hcd.date_util")
local M=require("hcd.data")
local n=0
local function eq(actual,expected,label)
    n=n+1
    if actual~=expected then error((label or "test")..": expected "..tostring(expected)..", got "..tostring(actual),2) end
end
eq(D.is_leap(2000),true,"century leap")
eq(D.is_leap(1900),false,"century nonleap")
eq(D.days_in_month(2024,2),29,"February")
eq(D.valid("2024-02-29"),true,"valid leap day")
eq(D.valid("2025-02-29"),false,"invalid leap day")
eq(D.iso_day("2026-11-23T12:34:56Z"),"2026-11-23","ISO timestamp")
eq(D.add_days("2026-10-31",1),"2026-11-01","month boundary")
eq(D.add_days("2024-03-01",-1),"2024-02-29","leap boundary")
eq(#D.month_grid(2026,11,1),35,"Sunday grid")
eq(#D.month_grid(2026,11,2),42,"Monday grid")
eq(D.month_grid(2026,11,1)[1],"2026-11-01","Sunday first")
eq(D.month_grid(2026,11,2)[1],"2026-10-26","Monday first")
eq(D.range("2026-10-27","2026-10-31"),"Oct 27, 2026 – Oct 31, 2026","range")
eq(D.range("2026-10-27","2026-10-27"),"Oct 27, 2026","same date")
local book={id=1,title="A",pages=200,cached_image={url="https://covers/a.jpg"},cached_contributors={{author={name="Author"},primary=true}}}
local function journal(id,day,meta,event,book_id)
    return {id=id,book_id=book_id or 1,action_at=day.."T12:00:00Z",journal_date=day,event=event or "progress_updated",metadata=meta,book=book}
end
local rows={
    journal(1,"2026-10-20",{progress_pages=40},"user_book_read_started"),
    journal(2,"2026-10-25",{progress_pages=50}),
    journal(3,"2026-10-26",{pages_read=20}),
    journal(4,"2026-10-27",{previous_page=70,page=89}),
    journal(5,"2026-10-27",{pages_delta=10},nil,2),
    journal(6,"2026-10-27",{previous_progress=0.2,progress=0.79},nil,3),
    journal(7,"2026-10-28",{progress_pages=5},"user_book_read_started"),
    journal(8,"2026-10-29",{progress_pages=15}),
}
local activity=M.activity(rows,{},"2026-10-01","2026-10-31")
eq(activity.days["2026-10-27"].total_pages,147,"multi book daily total")
local three=M.activity({
    journal(1,"2026-10-27",{pages_read=19},nil,1),
    journal(2,"2026-10-27",{pages_read=128},nil,2),
    journal(3,"2026-10-27",{pages_read=25},nil,3),
}, {},"2026-10-01","2026-10-31")
eq(three.days["2026-10-27"].total_pages,172,"19 + 128 + 25")
eq(activity.days["2026-10-29"].total_pages,10,"reread reset")
eq(activity.days["2026-10-21"],nil,"empty day")
local spans=M.lanes(activity,D.month_grid(2026,10,1))
eq(spans["2026-10-20"].lanes["1"]~=nil,true,"first span")
eq(spans["2026-10-21"].lanes["1"],nil,"gap breaks span")
eq(spans["2026-10-25"].lanes["1"]~=nil,true,"later span")
eq(#spans["2026-10-27"].finishes>=2,true,"finish covers")
local no_progress=M.activity({journal(9,"2026-10-18",{},"status_currently_reading",9)},{{book_id=9,book=book,started_at="2026-10-18",finished_at="2026-10-25"}},"2026-10-01","2026-10-31")
eq(no_progress.active_days,0,"0-page status/read events excluded from calendar")
local with_range=M.activity({journal(10,"2026-10-20",{pages_read=28},nil,1)},{{book_id=1,book=book,started_at="2026-10-20",finished_at="2026-10-27"}},"2026-10-01","2026-10-31")
eq(with_range.days["2026-10-20"].books[1].started_at,"2026-10-20","read range attaches to progressed book")
eq(with_range.days["2026-10-20"].books[1].finished_at,"2026-10-27","read finish attaches to progressed book")
eq(with_range.days["2026-10-27"],nil,"finish day without pages stays empty")
local days={}
for day=25,31 do days[string.format("2026-10-%02d",day)]={active=true} end
for day=1,22 do days[string.format("2026-11-%02d",day)]={active=true} end
local current,best=M.streak(days,"2026-11-23")
eq(current,29,"streak through yesterday")
eq(best,29,"best streak")
days["2026-11-23"]={active=true}
current=M.streak(days,"2026-11-23")
eq(current,30,"streak including today")
days["2026-11-22"]=nil;days["2026-11-23"]=nil
current=M.streak(days,"2026-11-23")
eq(current,0,"broken streak")
local goals=M.goals({{id=1,metric="hour",goal=10,progress=36000,end_date="2026-12-31"}},2026)
eq(goals[1].progress,10,"hour seconds conversion")
eq(goals[1].percent,100,"hour percent")
local reading=M.reading({{id=1,book_id=1,book=book,edition={cached_image={url="https://covers/edition.jpg"}},user_book_reads={{id=3,started_at="2026-10-02",finished_at=nil,progress_pages=75,edition={cached_image={url="https://covers/read.jpg"}}},{id=2,started_at="2026-09-01",finished_at="2026-09-30"}}}})
eq(reading[1].cover,"https://covers/read.jpg","active edition cover")
eq(reading[1].author,"Author","author")
eq(reading[1].progress_pages,75,"active read")
eq(M.journal_delta({pages_read=19},200,0),19,"direct delta")
eq(M.journal_delta({from_page=10,to_page=20},200,0),10,"from to")
eq(M.journal_delta({previous_progress=25,progress=50},200,0),50,"percentage")
-- Regression test: KOReader rapidjson decodes JSON null as a truthy function
local fake_null=function() end
days[fake_null]={active=true}
local sc,sb=M.streak(days,"2026-11-23")
eq(sc,0,"streak ignores function key")
eq(sb,28,"best streak ignores function key")
local null_goals=M.goals({{id=2,metric="book",goal=12,progress=5,description=fake_null,completed_at=fake_null,end_date="2026-12-31",state="active"}},2026)
eq(null_goals[1].description,nil,"goal description strips function null")
eq(null_goals[1].is_completed,false,"active goal with null completed_at is not completed")
local null_read=M.reading({{id=2,book_id=1,book=book,edition={title=fake_null,pages=200},user_book_reads={{id=5,started_at="2026-11-01",finished_at=fake_null,progress_pages=100}}}})
eq(null_read[1].title,"A","reading title falls back when edition.title is null")
eq(null_read[1].progress_pages,100,"reading detects open read when finished_at is function null")
print("OK: "..n.." pure Lua assertions")
