window.EventsNew =
  init: ->
    form = $('#new_event')
    form.steps
      headerTag: ".legend"
      bodyTag: ".step"
      autoFocus: true
      labels: {
        previous: '<i class="fa fa-arrow-left"></i>' + Airesis.i18n.buttons.goBack
        next: Airesis.i18n.buttons.next + '<i class="fa fa-arrow-right"></i>'
        finish: Airesis.i18n.buttons.eventsFinish
      }
      onStepChanging: (e, currentIndex, newIndex)->
        fv = form.data('formValidation')
        $container = form.find('.step.current')
        fv.validateContainer($container);
        isValidStep = fv.isValidContainer($container)
        !(isValidStep is false || isValidStep is null)
      onStepChanged: (event, currentIndex, priorIndex)->
        setTimeout (->
          if !EventsEdit.votation
            EventsNew.mapManager.refresh()
          return
        ), 1000
      onFinishing: (e, currentIndex)->
        fv = form.data('formValidation')
        $container = form.find('.step.current')
        fv.validateContainer($container)
        isValidStep = fv.isValidContainer($container)
        !(isValidStep is false || isValidStep is null)
      onFinished: (e, currentIndex)->
        form.formValidation('defaultSubmit')
      onInit: (e, currentIndex)->
        form.find('[role="menuitem"]').addClass('btn').addClass('blue')

    $('#create_event_dialog:not(".open")').foundation('reveal', 'open', {
      closeOnBackgroundClick: false,
      closeOnEsc: false
    })

    start_end_fdatetimepicker $('#event_starttime'), $("#event_endtime");
    @initMunicipalityInput()
    @initMapManager()

    new AiresisFormValidation(form)
  initMunicipalityInput: ->
    input = $('#event_meeting_attributes_place_attributes_municipality_id')
    Airesis.select2town(input)
    input.change (e)->
      $('#new_event').formValidation('revalidateField', input.attr('name'))
  initMapManager: ->
    if !EventsEdit.votation
      EventsNew.mapManager = new Airesis.MapManager('create_map_canvas')
