# Carregar os pacotes necessários
library(shiny)
library(leaflet)
library(DBI)
library(RPostgres)
library(pool)
library(ggplot2)
library(dplyr)
library(lubridate)
library(plotly)
library(shinycssloaders)  # Para adicionar spinners durante o carregamento
library(memoise)         # Para caching

# Definir a UI
ui <- fluidPage(
  titlePanel("Interactive Map OG2OW"),
  sidebarLayout(
    sidebarPanel(
      width = 5,
      h3("Select a Plataform"),
      uiOutput("platform_selector"),
      h3("Select a Turbine"),
      uiOutput("turbina_selector"),
      h3("Platforms Details"),
      tableOutput("detalhesPlataforma"),
      verbatimTextOutput("mediaHistorica"),
      plotlyOutput("graficoPotencial") %>% withSpinner()
    ),
    mainPanel(
      width = 7,
      leafletOutput("mapaPlataformas", height = "700px") %>% withSpinner()
    )
  )
)

# Insert DB crendetials HERE!
server <- function(input, output, session) {
  #Sys.setenv(DB_HOST = "localhost")
  #Sys.setenv(DB_NAME = "Example_Data")
  #Sys.setenv(DB_USER = "Example_Name")
  #Sys.setenv(DB_PASS = "Example_Pasword123")
  #Sys.setenv(DB_PORT = "5432")
  

  

  
  # Configurações de conexão usando pool
  pool <- dbPool(
    RPostgres::Postgres(),
    dbname = Sys.getenv("DB_NAME"),
    host = Sys.getenv("DB_HOST"),
    port = Sys.getenv("DB_PORT"),
    user = Sys.getenv("DB_USER"),
    password = Sys.getenv("DB_PASS")
  )
  
  onStop(function() {
    poolClose(pool)
  })
  
  # Cache para consultas de plataformas
  get_plataformas <- memoise(function(pool, query) {
    dbGetQuery(pool, query)
  })
  
  # Query para buscar as plataformas com média de potencial
  query_plataformas <- "
    SELECT 
      p.nome_instalacao, 
      p.latitude, 
      p.longitude, 
      p.id,
      AVG(e.valor) AS media_potencial
    FROM 
      Plataformas p
    LEFT JOIN 
      Eletricidade e 
    ON 
      p.id = e.plataforma_id
    GROUP BY 
      p.nome_instalacao, p.latitude, p.longitude, p.id
  "
  
  
  plataformas <- reactive({
    req(pool)
    tryCatch(
      get_plataformas(pool, query_plataformas),
      error = function(e) {
        showNotification("Erro ao buscar dados das plataformas.", type = "error")
        return(NULL)
      }
    )
  })
  
  # Cache para consultas de turbinas
  get_turbinas <- memoise(function(pool, query) {
    dbGetQuery(pool, query)
  })
  
  # Query para buscar todas as turbinas disponíveis
  turbinas_query <- "
    SELECT id, modelo FROM turbinas
  "
  
  turbinas <- reactive({
    req(pool)
    tryCatch(
      get_turbinas(pool, turbinas_query),
      error = function(e) {
        showNotification("Erro ao buscar dados das turbinas.", type = "error")
        return(NULL)
      }
    )
  })
  
  
  # Criar o seletor de plataformas na UI
  output$platform_selector <- renderUI({
    dados <- plataformas()
    if(is.null(dados)) return(NULL)
    selectInput("platform_select", "Select a Plataform:",
                choices = setNames(dados$id, dados$nome_instalacao),
                selected = NULL,
                multiple = FALSE)
  })
  
  # Criar o seletor de turbinas na UI
  output$turbina_selector <- renderUI({
    dados <- turbinas()
    if(is.null(dados)) return(NULL)
    selectInput("turbina_select", "Select a Turbine:",
                choices = setNames(dados$id, dados$modelo),
                selected = NULL,
                multiple = FALSE)
  })
  
  # Criar o mapa com clustering
  output$mapaPlataformas <- renderLeaflet({
    dados <- plataformas()
    req(dados)
    
    # Adicionar coluna para cor baseada na média do potencial
    dados <- dados %>%
      mutate(cor = case_when(
        media_potencial > 5000 ~ "green",
        media_potencial > 2500 ~ "orange",
        TRUE ~ "red"
      ))
    
    leaflet(data = dados) %>%
      addTiles() %>%
      addCircleMarkers(
        lng = ~longitude, 
        lat = ~latitude, 
        popup = ~paste0("<strong>", nome_instalacao, "</strong><br>Average Wind Potential: ", round(media_potencial, 2)),
        label = ~nome_instalacao,
        labelOptions = labelOptions(direction = "auto", textsize = "13px"),
        color = ~cor,
        radius = 6,
        layerId = ~id,
        clusterOptions = markerClusterOptions()  # Ativa o clustering
      ) %>%
      addLegend("bottomright", 
                colors = c("green", "orange", "red"),
                labels = c("Mean > 5MW", "0 < Mean ≤ 5MW", "Mean ≤ 2.5MW"),
                title = "Average Wind Potential",
                opacity = 1) %>%
      setView(
        lng = mean(dados$longitude, na.rm = TRUE), 
        lat = mean(dados$latitude, na.rm = TRUE), 
        zoom = 4
      )
  })
  
  # Valor reativo para armazenar o ID da plataforma selecionada
  selected_plataforma <- reactiveVal(NULL)
  
  # Valor reativo para armazenar o ID da turbina selecionada
  selected_turbina <- reactiveVal(NULL)
  
  # Observa cliques nos marcadores
  observeEvent(input$mapaPlataformas_marker_click, {
    click <- input$mapaPlataformas_marker_click
    if (is.null(click))
      return()
    selected_plataforma(click$id)
    updateSelectInput(session, "platform_select", selected = click$id)
  })
  
  # Observa a seleção via selectInput de plataforma
  observeEvent(input$platform_select, {
    selected_plataforma(input$platform_select)
    
    # Centralizar o mapa na plataforma selecionada
    platform <- plataformas() %>% filter(id == input$platform_select)
    
    if(nrow(platform) == 1){
      leafletProxy("mapaPlataformas") %>% 
        setView(lng = platform$longitude, lat = platform$latitude, zoom = 6) %>%
        clearPopups() %>%
        addPopups(lng = platform$longitude, lat = platform$latitude, 
                  popup = paste0("<strong>", platform$nome_instalacao, "</strong><br>Mean Potential: ", 
                                 round(platform$media_potencial, 2)))
    }
  })
  
  # Observa a seleção via selectInput de turbina
  observeEvent(input$turbina_select, {
    selected_turbina(input$turbina_select)
  })
  
  # Buscar detalhes da plataforma e série histórica com a turbina selecionada
  detalhes <- reactive({
    req(selected_plataforma())
    req(selected_turbina())
    
    # Obter detalhes da plataforma
    query_detalhes <- sprintf("SELECT nome_instalacao, latitude, longitude FROM Plataformas WHERE id = %s", selected_plataforma())
    detalhes_plat <- tryCatch(
      dbGetQuery(pool, query_detalhes),
      error = function(e) {
        showNotification("Error Searching Platform Details.", type = "error")
        return(NULL)
      }
    )
    
    # Obter série histórica para a turbina selecionada
    query_hist <- sprintf("SELECT data_hora, valor FROM Eletricidade WHERE plataforma_id = %s AND turbina_id = %s ORDER BY data_hora", 
                          selected_plataforma(), selected_turbina())
    historico <- tryCatch(
      dbGetQuery(pool, query_hist),
      error = function(e) {
        showNotification("Error Searching Platform", type = "error")
        return(NULL)
      }
    )
    
    if(is.null(detalhes_plat) || is.null(historico)){
      return(NULL)
    }
    
    # Processar a série histórica para obter média mensal
    if(nrow(historico) > 0){
      historico <- historico %>%
        mutate(data_mes = floor_date(as.Date(data_hora), "month")) %>%
        group_by(data_mes) %>%
        summarise(media_valor = mean(valor, na.rm = TRUE)) %>%
        ungroup()
      
      media_historica <- mean(historico$media_valor, na.rm = TRUE)
    } else {
      media_historica <- NA
    }
    
    list(detalhes = detalhes_plat, historico = historico, media = media_historica)
  })
  
  # Mostrar detalhes da plataforma
  output$detalhesPlataforma <- renderTable({
    validate(
      need(detalhes(), "Platfrom Details not Available.")
    )
    detalhes <- detalhes()$detalhes
    data.frame(
      "Installation Name" = detalhes$nome_instalacao,
      "Latitude" = detalhes$latitude,
      "Longitude" = detalhes$longitude,
      check.names = FALSE
    )
  })
  
  # Mostrar a média histórica abaixo dos detalhes da plataforma
  output$mediaHistorica <- renderPrint({
    validate(
      need(detalhes(), "Historical average not available.")
    )
    media <- detalhes()$media
    if(!is.na(media)){
      cat("Historical Average Electric Potential (kW):", round(media, 2))
    } else {
      cat("Historical Average Electric Potential: No Avaliable")
    }
  })
  
  # Mostrar gráfico de potencial por tempo com média histórica
  output$graficoPotencial <- renderPlotly({
    validate(
      need(detalhes(), "Gráfico de potencial não disponível.")
    )
    historico <- detalhes()$historico
    media_historica <- detalhes()$media
    
    if(nrow(historico) == 0){
      plot_ly() %>% layout(title = "Nenhum dado de potencial disponível.")
    } else {
      p <- ggplot(historico, aes(x = data_mes, y = media_valor)) +
        geom_line(color = "blue") +
        geom_point(color = "blue") +
        labs(title = "Electric Potential Over Time",
             subtitle = "Month Mean",
             x = "Year",
             y = "Eletric Potential (kW)") +
        scale_x_date(date_labels = "%Y", date_breaks = "12 months") +
        theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
        theme_minimal() +
        geom_hline(yintercept = media_historica, linetype = "dashed", color = "red")
      
      ggplotly(p, tooltip = c("x", "y"))
    }
  })
}

# Rodar o Shiny App
shinyApp(ui, server)
