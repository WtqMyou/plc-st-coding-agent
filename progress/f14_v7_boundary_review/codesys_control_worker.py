# Executed by CODESYS IronPython 2.7, in an isolated project copy.
from __future__ import print_function
from scriptengine import *
import hashlib
import io
import json
import os
import sys
import traceback

job=json.loads(io.open(sys.argv[1],encoding='utf-8').read())
report=dict(nonce=job['nonce'],status='tool_error',phase='initializing',simulation_only=True,
            native_execution=False,diagnostics=[],samples=[],cleanup_errors=[])
project=None
onlineapp=None
device=None

def save():
    with io.open(job['result'], 'w',encoding='utf-8') as target:
        target.write(unicode(json.dumps(report,ensure_ascii=False,indent=2)))

def phase(name):
    report['phase']=name
    save()

def require_simulation():
    if device is None or not device.get_simulation_mode():
        raise RuntimeError('Simulation must be verified before every online operation')

def snapshot():
    names=job['watch_names']
    return {name:unicode(onlineapp.read_value('PLC_PRG.'+name)) for name in names}

def stop_if_needed():
    require_simulation()
    if onlineapp.application_state!=ApplicationState.stop:
        onlineapp.stop()

def normalized(values):
    result={}
    types=('BOOL','INT','DINT','LINT','SINT','UINT','UDINT','ULINT','USINT','WORD','DWORD','LWORD','BYTE')
    for key,value in values.items():
        prefix,separator,tail=value.partition('#')
        result[key]=tail if separator and prefix.upper() in types else value
    return result

try:
    if job['simulation_only'] is not True:raise RuntimeError('No physical device execution is supported')
    project=projects.open(job['template'])
    project.save_as(job['project'])
    phase('isolated_project_created')
    children=project.get_children(recursive=True)
    apps=[x for x in children if getattr(x,'is_application',False)]
    if len(apps)!=1:raise RuntimeError('Expected exactly one application')
    app=apps[0]
    devices=[x for x in children if getattr(x,'is_device',False) and hasattr(x,'get_simulation_mode')]
    if len(devices)!=1:raise RuntimeError('Expected exactly one simulated device candidate')
    device=devices[0]
    report['device_name']=unicode(device.get_name())
    tasks=[x for x in children if getattr(x,'is_task',False)]
    if len(tasks)!=1:raise RuntimeError('Expected one isolated cyclic task')
    task=tasks[0]
    if task.kind_of_task!=KindOfTask.Cyclic:raise RuntimeError('Expected cyclic task')
    before=[list(task.pous[i]) for i in range(len(task.pous))]
    if len(before)>1:raise RuntimeError('Unexpected extra task calls')
    if before:task.pous.replace(0,'PLC_PRG','V2 standard block semantic probe')
    else:task.pous.add('PLC_PRG','V2 standard block semantic probe')
    report['task']=dict(name=unicode(task.get_name()),kind=unicode(task.kind_of_task),
        interval=unicode(task.interval),interval_unit=unicode(task.interval_unit),
        calls_before=before,calls_after=[list(task.pous[i]) for i in range(len(task.pous))])
    for definition in job.get('duts',[]):
        if app.find(definition['name']):raise RuntimeError('Unexpected existing DUT')
        dut=app.create_dut(definition['name'])
        dut.textual_declaration.replace(definition['declaration'])
    if app.find('FB'):raise RuntimeError('Unexpected FB in frozen template')
    fb=app.create_function_block('FB')
    fb.textual_declaration.replace(job['fb']['declaration'])
    fb.textual_implementation.replace(job['fb']['implementation'])
    fb.build_properties.link_always=True
    programs=app.find('PLC_PRG')
    if len(programs)>1:raise RuntimeError('Multiple PLC_PRG objects')
    program=programs[0] if programs else app.create_program('PLC_PRG')
    program.textual_declaration.replace(job['program']['declaration'])
    program.textual_implementation.replace(job['program']['implementation'])
    program.build_properties.link_always=True
    phase('two_instance_program_installed')
    for category in system.get_message_categories():system.clear_messages(category)
    app.build()
    app.generate_code()
    messages=[]
    for category in system.get_message_categories():messages.extend(system.get_message_objects(category))
    report['diagnostics']=[unicode(m) for m in messages]
    if any(m.severity in (Severity.Error,Severity.FatalError) for m in messages):
        report['status']='build_failed'
        raise RuntimeError('Combined FB and two-instance calling program did not compile')
    report['combined_build']='passed'
    project.save()
    phase('combined_build_passed')
    device.set_simulation_mode(True)
    require_simulation()
    report['simulation_mode_before_login']=device.get_simulation_mode()
    project.save()
    onlineapp=online.create_online_application(app)
    onlineapp.timeout=15000
    phase('logging_into_local_simulator')
    require_simulation()
    onlineapp.login(OnlineChangeOption.Never,False)
    require_simulation()
    report['logged_in']=onlineapp.is_logged_in
    phase('local_simulator_logged_in')
    stop_if_needed()
    onlineapp.reset(ResetOption.Cold)
    system.delay(100)
    report['initial_values']=snapshot()
    report['initial_values_normalized']=normalized(report['initial_values'])
    if report['initial_values_normalized']['step']!='0' or report['initial_values_normalized']['testComplete'].upper()!='FALSE':
        raise RuntimeError('Simulator did not start from a fresh test instance')
    require_simulation()
    onlineapp.start()
    report['native_execution']=True
    phase('running_local_simulator')
    for i in range(100):
        system.delay(100)
        values=snapshot()
        report['samples'].append(values)
        if values['testComplete'].upper()=='TRUE':break
    require_simulation()
    stop_if_needed()
    report['final_values']=snapshot()
    report['final_values_normalized']=normalized(report['final_values'])
    report['simulation_mode_after_stop']=device.get_simulation_mode()
    values=report['final_values_normalized']
    expected=job['expected']
    report['expected']=expected
    report['observed_expected']=all(values[k].upper()==unicode(v).upper() for k,v in expected.items())
    report['status']='passed' if report['observed_expected'] else 'test_failed'
    phase('simulator_result_recorded')
except Exception:
    report['error']=traceback.format_exc()
finally:
    if onlineapp is not None:
        try:
            require_simulation()
            if onlineapp.is_logged_in:
                stop_if_needed()
                onlineapp.logout()
            onlineapp.Dispose()
            report['simulator_logged_out']=True
        except Exception:report['cleanup_errors'].append(traceback.format_exc())
    if project is not None:
        try:
            project.save()
            project.close()
            report['project_closed']=True
        except Exception:report['cleanup_errors'].append(traceback.format_exc())
    save()
