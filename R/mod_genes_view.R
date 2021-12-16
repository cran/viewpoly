#' genes_view UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @importFrom shinyjs inlineCSS
#' 
#' @noRd 
#'
#' @importFrom shiny NS tagList 
mod_genes_view_ui <- function(id){
  ns <- NS(id)
  tagList(
    fluidPage(
      verticalLayout(
        fluidRow(
          inlineCSS(".form-group {margin-bottom: 0;}
                                .irs-with-grid {bottom: 0px;}
                                .irs-grid {height: 13px;}
                                .irs-grid-text {height: 0px;}
                                "
          ),
          column(width = 12,
                 div(style = "position:absolute;right:1em;", 
                     actionButton(ns("exit"), "Exit",icon("times-circle"), class = "btn btn-danger"),  br(), br(),
                     actionButton(ns("goMap"), "Next",icon("arrow-circle-right"), class = "btn btn-success")
                 )
          ),
          tags$h2(tags$b("VIEWgenome")), br(), hr(),
          
          column(6,
                 column(6,
                        box(width = 12, solidHeader = TRUE, status="info", title = h4("Select phenotypes"),
                            pickerInput(ns("phenotypes"),
                                        label = h4("Phenotypes:"),
                                        choices = "This will be updated",
                                        selected = "This will be updated",
                                        options = list(
                                          `actions-box` = TRUE, 
                                          size = 10,
                                          `selected-text-format` = "count > 3"
                                        ), 
                                        multiple = TRUE),
                        ), br(),
                 ),
                 column(6,
                        box(width = 12, solidHeader = TRUE, status="info", title = h4("Select linkage group"),
                            selectInput(inputId = ns("group"), label = p("Linkage group:"), choices = 1:15, selected = 1),
                        ), br(),
                 )
          ),
        ), hr(),
        wellPanel(
          sliderInput(ns("range"), "Map range (cM)", min = 0, max = 300,
                      value = c(0, 20), step = 1), 
          uiOutput(ns("interval"))
        ),
        box(width = 12, solidHeader = TRUE, collapsible = TRUE,  collapsed = TRUE, status="primary", title = h4("QTL profile"),
            column(2,
                   downloadBttn(ns('bn_download'), style = "gradient", color = "royal")
            ),
            column(10,
                   radioButtons(ns("fformat"), "File type", choices=c("png","tiff","jpeg","pdf"), selected = "png", inline = T)
            ), br(),
            column(12,
                   hr(),
                   plotlyOutput(ns("plot_qtl"))
            )
        ), br(),
        box(width = 12, solidHeader = TRUE, collapsible = TRUE,  collapsed = FALSE, status="primary", title = h4("Linkage Map position (cM) x Physical position (Mp)"),
            column(2,
                   downloadBttn(ns('bn_download_phi'), style = "gradient", color = "royal")
            ),
            column(10,
                   radioButtons(ns("fformat_phi"), "File type", choices=c("png","tiff","jpeg","pdf"), selected = "png", inline = T)
            ), br(),
            column(12,
                   hr(),
                   plotlyOutput(ns("plot_pos"))
            )
        ), br(),
        box(width = 12, height = 1000, solidHeader = TRUE, collapsible = TRUE,  collapsed = FALSE, status="primary", title = h4("JBrowseR"),
            column(12,
                   column(6,
                          actionButton(ns("create_server"), "Open JBrowseR",icon("power-off"))
                   ),
                   column(6,
                          div(style = "position:absolute;right:1em;", 
                              p("Local server:"),
                              switchInput(ns("reset_server"), value = TRUE)
                          )
                   )
            ),
            column(12, br(), hr(),
                   JBrowseROutput(ns("browserOutput"))
            ), br()),
        box(width = 12, solidHeader = TRUE, collapsible = TRUE,  collapsed = FALSE, status="primary", title = h4("Annotation table"),
            DT::dataTableOutput(ns("genes_ano"))
        )
      )
    )
  )
}

#' genes_view Server Functions
#'
#' @importFrom JBrowseR serve_data renderJBrowseR assembly track_feature tracks default_session JBrowseR JBrowseROutput 
#' @importFrom plotly event_data layout
#' @importFrom shinyjs inlineCSS
#' @importFrom dplyr `%>%`
#'
#' @noRd 
mod_genes_view_server <- function(input, output, session, 
                                  loadMap, loadQTL,
                                  loadJBrowse_fasta, loadJBrowse_gff3, loadJBrowse_vcf, loadJBrowse_align, loadJBrowse_wig, 
                                  loadExample,
                                  parent_session){
  ns <- session$ns
  
  pheno <- LG <- l.dist <- g.dist <- high <- mk.names <- track_variant <- track_alignments <- track_wiggle <- NULL
  start <- end <- NULL
  
  observeEvent(input$exit, {
    stopApp()
  })
  
  observe({
    # Dynamic linkage group number
    if(!is.null(loadMap())){
      group_choices <- as.list(1:length(loadMap()$d.p1))
      names(group_choices) <- 1:length(loadMap()$d.p1)
    } else if(!is.null(loadQTL())){
      group_choices <- as.list(1:length(unique(loadQTL()$selected_mks$LG)))
      names(group_choices) <- 1:length(unique(loadQTL()$selected_mks$LG))
    } else {
      group_choices <- as.list("Upload map or QTL data in `upload` session.")
      names(group_choices) <-  "Upload map or QTL data in `upload` session."
    }
    
    updateSelectInput(session, "group",
                      label="Linkage group",
                      choices = group_choices,
                      selected= group_choices[[1]])
    
    # Dynamic QTL
    if(!is.null(loadQTL())){
      pheno_choices <- as.list(unique(loadQTL()$profile$pheno))
      names(pheno_choices) <- unique(loadQTL()$profile$pheno)
      
      updatePickerInput(session, "phenotypes",
                        label = "Select phenotypes",
                        choices = pheno_choices,
                        selected=unlist(pheno_choices)[1])
    } else {
      updatePickerInput(session, "phenotypes",
                        label = "Phenotype:",
                        choices = "Upload QTL information to update",
                        selected= "Upload QTL information to update")
    }
  })
  
  observeEvent(input$goMap, {
    updateTabsetPanel(session = parent_session, inputId = "viewpoly",
                      selected = "map")
  })
  
  # Plot QTL bar
  qtl.int <- reactive({
    if(!is.null(loadQTL())){
      data <- loadQTL()$qtl_info %>% filter(.data$pheno %in% input$phenotypes & .data$LG == input$group)
      
      if(dim(data)[1] == 0) return(p(" "))
      
      data <- data[order(data$Pos_lower, data$Pos_upper),]
      command <- paste0(round(data$Pos_lower,0), ":", round(data$Pos_upper, 0))
      seqs <- list()
      for(i in 1:length(command))
        seqs[[i]] <- eval(parse(text = command[i]))
      
      maps <- lapply(loadMap()$maps, function(x) {
        y <- x$l.dist
        names(y) <- x$mk.names
        y
      })
      
      max_updated <- map_summary(left.lim = input$range[1], 
                                 right.lim = input$range[2], 
                                 ch = input$group, maps = maps, 
                                 d.p1 = loadMap()$d.p1, d.p2 = loadMap()$d.p2)[[5]]
      
      qtls_pos <- Reduce(union, seqs)
      chr_all <- 0:max_updated
      
      idx.comp <-  chr_all %in% qtls_pos
      int <- chr_all[sequence(rle(idx.comp)$length) == 1]
      
      int <- (int*100)/max_updated
      # add start and end
      ints_all <- unique(c(0,int, 100))
      # add qtls 
      qtls <- (unique(sort(data$Pos))*100)/max_updated
      qtls <- sort(c(qtls -0.3, qtls +0.3))
      
      labs <- c(rep("int", length(ints_all)), rep(c("red","#34495E "), length(qtls/2)))
      labs <- labs[order(c(ints_all, qtls))]
      labs[which(labs == "red")-1] <- "#34495E "
      labs[which(labs == "int")] <- "#D5D8DC"
      labs <- labs[-length(labs)]
      
      ints_all <- diff(sort(c(ints_all, qtls)))
      
      # Each interval add small blank space to the scale - need to remove
      reduce <- cumsum(ints_all)[length(cumsum(ints_all))] - 99.7
      ints_all[which(labs != "red")] <- ints_all[which(labs != "red")] - reduce
      
      # Add gradient colors
      OrRd <- c("#FFF7EC", "#FEE8C8", "#FDD49E", "#FDBB84", "#FC8D59", "#EF6548", "#D7301F", "#B30000", "#7F0000")
      if(length(labs[which(labs == "red")]) < 3){
        qtl.colors <- OrRd[1:7][-c(1:5)][1:length(labs[which(labs == "red")])]
      } else {
        qtl.colors <- OrRd[1:length(labs[which(labs == "red")])]
      }
      
      labs[which(labs == "red")][order(as.numeric(data$Pval), decreasing = T)] <- qtl.colors
      
      divs <- paste0("display:inline-block; width: ", ints_all ,"% ; background-color: ", labs, ";")
      if(!is.null(input$phenotypes)){
        divs_lst <- list()
        for(i in 1:length(divs)){
          divs_lst[[i]] <- div(id= paste0("belowslider",i), style= divs[i], p())
        }
      }
      p(divs_lst, "QTL")
    } else {
      return(p(" "))
    }
  })
  
  output$interval <- renderUI({ 
    qtl.int()
  })
  
  # Plot QTL profile
  output$plot_qtl <- renderPlotly({
    if(!is.null(loadQTL())){
      idx <- which(unique(loadQTL()$profile$pheno) %in% input$phenotypes)
      pl <- plot_profile(profile = loadQTL()$profile, qtl_info = loadQTL()$qtl_info, selected_mks = loadQTL()$selected_mks,
                         pheno.col = idx,
                         lgs.id = as.numeric(input$group),
                         range.min = input$range[1],
                         range.max = input$range[2], 
                         by_range=T, 
                         software = loadQTL()$software)
      ggplotly(source = "qtl_profile", pl, tooltip=c("Trait","Position (cM)")) %>% layout(legend = list(orientation = 'h', y = -0.3))
    } else 
      stop("Upload the QTL information in upload session to access this feature.")
  })
  
  # cM x Mb
  output$plot_pos <- renderPlotly({
    if(!is.null(loadMap()))
      if(loadMap()$software == "polymapR") stop("Feature not implemented for software polymapR.") 
    
    if(is.null(loadMap()$ph.p1)) stop("Upload map information in the upload session to access this feature.")
    
    map.lg <- loadMap()$maps[[as.numeric(input$group)]]
    
    map.lg$high <- map.lg$g.dist
    map.lg$high[round(map.lg$l.dist,5) < input$range[1] | round(map.lg$l.dist,5) > input$range[2]] <- "black"
    map.lg$high[round(map.lg$l.dist,5) >= input$range[1] & round(map.lg$l.dist,5) <= input$range[2]] <- "red"
    
    map.lg$high <- as.factor(map.lg$high)
    p <- ggplot(map.lg, aes(x=l.dist, y = g.dist/1000, colour = high, text = paste("Marker:", mk.names, "\n", 
                                                                                   "Genetic:", round(l.dist,2), "cM \n",
                                                                                   "Genomic:", g.dist/1000, "Mb"))) +
      geom_point() + scale_color_manual(values=c('black','red')) + 
      theme(legend.position = "none") + 
      labs(x = "Linkage map (cM)", y = "Reference genome (Mb)") +
      theme_bw()
    
    max_updated = reactive({
      dist <- loadMap()$maps[[as.numeric(input$group)]]$l.dist
      max.range <- max(dist)
      max.range
    })
    
    observeEvent(max_updated, {
      updateSliderInput(inputId = "range", max = round(max_updated(),2))
    })
    
    ggplotly(p, tooltip="text") %>% layout(showlegend = FALSE)
  })
  
  # Open JBrowser server 
  button <- eventReactive(input$create_server, {
    
    if(!is.null(loadJBrowse_fasta())){
      if(loadJBrowse_fasta() != "") {
        path.fa <- loadJBrowse_fasta()
      } else path.fa <- NULL
    } else path.fa <- NULL
    
    if(!is.null(loadJBrowse_gff3())){
      if(loadJBrowse_gff3() != "") {
        path.gff <- loadJBrowse_gff3()
      } else path.gff <- NULL
    } else path.gff <- NULL
    
    if(!is.null(loadJBrowse_vcf())){
      if(loadJBrowse_vcf() != ""){
        path.vcf <- loadJBrowse_vcf()
      } else path.vcf <- NULL
    } else path.vcf <- NULL
    
    if(!is.null(loadJBrowse_align())){
      if(loadJBrowse_align() != "") {
        path.align <- loadJBrowse_align()
      } else path.align <- NULL
    } else path.align <- NULL
    
    if(!is.null(loadJBrowse_wig())){
      if(loadJBrowse_wig() != "") {
        path.wig <- loadJBrowse_wig()
      } else path.wig <- NULL
    } else path.wig <- NULL
    
    if(is.null(loadJBrowse_fasta()) & !is.null(loadExample())){
        path.fa <- loadExample()$fasta
        path.gff <- loadExample()$gff3
        # Add other tracks
        # variants_track <- track_variant()
        # alignments_track <- track_alignments()
    } else if(is.null(loadJBrowse_fasta())){
      stop("Upload the genome information in upload session to access this feature.")
    }
    
    if(!grepl("^http", path.fa)){
      data_server <- serve_data(dirname(path.fa), port = 5000)
    } else data_server = NULL
    
    list(path.fa = path.fa, 
         path.gff = path.gff, 
         path.vcf = path.vcf, 
         path.align = path.align,
         path.wig = path.wig,
         data_server = data_server)
  })
  
  # Reset server
  reset <- reactive({
    if(!input$reset_server) { 
      if(!is.null(button()$data_server)){
        button()$data_server$stop_server()
      }
      return(TRUE)
    } else {
      return(FALSE)
    }
  })
  
  # Link the UI with the browser widget
  output$browserOutput <- renderJBrowseR({
    if(reset()) stop("The server is off, you can now submit new files in the upload tab.")
    
    if(!is.null(loadMap()))
      if(loadMap()$software == "polymapR") stop("Feature not implemented for software polymapR.")
    
    if(is.null(loadMap()$ph.p1)) stop("Upload map information in the upload session to access this feature.")
    
    if(!grepl("^http", button()$path.fa)){
      assembly <- assembly(
        paste0("http://127.0.0.1:5000/", basename(button()$path.fa)), 
        bgzip = TRUE
      )
    } else {
      assembly <- assembly(
        button()$path.fa, 
        bgzip = TRUE
      )
    }
    ## create configuration for a JB2 GFF FeatureTrack
    
    if(!is.null(button()$path.gff)){
      if(!grepl("^http", button()$path.gff)){
        annotations_track <- track_feature(
          paste0("http://127.0.0.1:5000/", basename(button()$path.gff)), 
          assembly
        )
      } else {
        annotations_track <- track_feature(
          button()$path.gff, 
          assembly
        )
      }
    } else annotations_track <- NULL
    
    if(!is.null(button()$path.vcf)){
      if(!grepl("^http", button()$path.vcf)){
        vcf_track <- track_variant(
          paste0("http://127.0.0.1:5000/", basename(button()$path.vcf)), 
          assembly
        )
      } else {
        vcf_track <- track_variant(
          button()$path.vcf, 
          assembly
        )
      }
    } else vcf_track <- NULL
    
    if(!is.null(button()$path.align)){
      if(!grepl("^http", button()$path.align)){
        align_track <- track_alignments(
          paste0("http://127.0.0.1:5000/", basename(button()$path.align)), 
          assembly
        )
      } else {
        align_track <- track_alignments(
          button()$path.align, 
          assembly
        )  
      }
    } else align_track <- NULL
    
    if(!is.null(button()$path.wig)){
      if(!grepl("^http", button()$path.wig)){
        wiggle_track <- track_wiggle(
          paste0("http://127.0.0.1:5000/", basename(button()$path.wig)), 
          assembly
        )
      } else {
        wiggle_track <- track_wiggle(
          button()$path.wig, 
          assembly
        )
      }
    } else wiggle_track <- NULL
    
    ## create the tracks array to pass to browser
    tracks <- tracks(annotations_track, vcf_track, align_track, wiggle_track)
    
    ## select default window
    group <- as.numeric(input$group)
    mk.pos <- loadMap()$maps[[group]]
    mks <- mk.pos[order(mk.pos$l.dist),]
    mks.range <- which(mks$l.dist >= input$range[1] &  mks$l.dist <= input$range[2])
    mks.range.1 <- mks$g.dist[mks.range[1]]
    mks.range.2 <- mks$g.dist[mks.range[length(mks.range)]]
    
    if(mks.range.1 > mks.range.2) stop("Inverted region. Check graphic `Genomic position (bp) x Linkage Map position (cM)`")
    
    tracks_set <- c(annotations_track, vcf_track, align_track, wiggle_track)
    
    theme <- JBrowseR::theme("#6c81c0", "#22284c")
    if(any(!is.null(tracks_set))){
      default_session <- default_session(
        assembly,
        tracks_set[which(!is.null(tracks_set))]
      )
      JBrowseR(
        "View",
        assembly = assembly,
        tracks = tracks,
        location = paste0(unique(mks$g.chr),":", mks.range.1,"..",mks.range.2), 
        defaultSession = default_session,
        theme = theme
      )
    } else {
      JBrowseR(
        "View",
        assembly = assembly,
        location = paste0(unique(mks$g.chr),":", mks.range.1,"..",mks.range.2), 
        theme = theme
      )
    }
  })
  
  output$genes_ano  <- DT::renderDataTable(server = FALSE, {
    if(!is.null(loadMap()))
      if(loadMap()$software == "polymapR") stop("Feature not implemented for software polymapR.")    
    
    if(is.null(loadMap()$ph.p1)) stop("Upload map information in the upload session to access this feature.")
    
    if(!is.null(button()$path.gff)) {
      group <- as.numeric(input$group)
      mks<- loadMap()$maps[[group]]
      mks <- mks[order(mks$l.dist),]
      mks.range <- which(mks$l.dist >= input$range[1] &  mks$l.dist <= input$range[2])
      mks.range.1 <- mks$g.dist[mks.range[1]]
      mks.range.2 <- mks$g.dist[mks.range[length(mks.range)]]
      
      df <- vroom(button()$path.gff, delim = "\t", skip = 3, col_names = F)
      colnames(df) <- c("seqid", "source", "type", "start", "end", "score", "strand", "phase", "attributes")
      df <- df %>% filter(start > mks.range.1 & end < mks.range.2)
      DT::datatable(df, extensions = 'Buttons',
                    options = list(
                      dom = 'Bfrtlp',
                      buttons = c('copy', 'csv', 'excel', 'pdf')
                    ),
                    class = "display")
    } else 
      stop("Upload annotation file (.gff3) in the upload session to access this feature.")
  })
  
  ## Downloads
  
  # QTL profile
  fn_downloadname <- reactive({
    seed <- sample(1:1000,1)
    if(input$fformat=="png") filename <- paste0("profile","_",seed,".png")
    if(input$fformat=="tiff") filename <- paste0("profile","_",seed,".tif")
    if(input$fformat=="jpeg") filename <- paste0("profile","_",seed,".jpg")
    if(input$fformat=="pdf") filename <- paste0("profile","_",seed,".pdf")
    return(filename)
  })
  
  # download profile 
  fn_download <- function()
  {
    idx <- which(unique(loadQTL()$profile$pheno) %in% input$phenotypes)
    pl <- plot_profile(profile = loadQTL()$profile, qtl_info = loadQTL()$qtl_info, selected_mks = loadQTL()$selected_mks,
                       pheno.col = idx,
                       lgs.id = as.numeric(input$group),
                       range.min = input$range[1],
                       range.max = input$range[2], 
                       by_range=T, 
                       software = loadQTL()$software)
    ggsave(pl, filename = fn_downloadname(), 
           width = 12.7, height = 8, units = "in")    
  }
  
  # download handler
  output$bn_download <- downloadHandler(
    filename = fn_downloadname,
    content = function(file) {
      fn_download()
      file.copy(fn_downloadname(), file, overwrite=T)
    }
  )
  
  # Download cMxMb
  fn_downloadname_phi <- reactive({
    seed <- sample(1:1000,1)
    if(input$fformat_phi=="png") filename <- paste0("linkageXphisical","_",seed,".png")
    if(input$fformat_phi=="tiff") filename <- paste0("linkageXphisical","_",seed,".tif")
    if(input$fformat_phi=="jpeg") filename <- paste0("linkageXphisical","_",seed,".jpg")
    if(input$fformat_phi=="pdf") filename <- paste0("linkageXphisical","_",seed,".pdf")
    return(filename)
  })
  
  # download  
  fn_download_phi <- function()
  {
    l.dist <- g.dist <- high <- mk.names <- NULL
    map.lg <- loadMap()$maps[[as.numeric(input$group)]]
    
    map.lg$high <- map.lg$g.dist
    map.lg$high[round(map.lg$l.dist,5) < input$range[1] | round(map.lg$l.dist,5) > input$range[2]] <- "black"
    map.lg$high[round(map.lg$l.dist,5) >= input$range[1] & round(map.lg$l.dist,5) <= input$range[2]] <- "red"
    
    map.lg$high <- as.factor(map.lg$high)
    p <- ggplot(map.lg, aes(x=l.dist, y = g.dist/1000, colour = high, text = paste("Marker:", mk.names, "\n", 
                                                                                   "Genetic:", round(l.dist,2), "cM \n",
                                                                                   "Genomic:", g.dist/1000, "Mb"))) +
      geom_point() + scale_color_manual(values=c('black','red')) + 
      labs(x = "Linkage map (cM)", y = "Reference genome (Mb)") +
      theme_bw() + theme(legend.position = "none") 
    
    ggsave(p, filename = fn_downloadname_phi(), 
           width = 12.7, height = 8, units = "in")    
  }
  
  # download handler
  output$bn_download_phi <- downloadHandler(
    filename = fn_downloadname_phi,
    content = function(file) {
      fn_download_phi()
      file.copy(fn_downloadname_phi(), file, overwrite=T)
    }
  )
  
}

## To be copied in the UI
# mod_genes_view_ui("genes_view_ui_1")

## To be copied in the server
# mod_genes_view_server("genes_view_ui_1")